/**
 * Vérification locale du relais, sans réseau ni Cloudflare.
 *
 * Exécute le Worker avec une base D1 simulée et un fetch simulé, puis vérifie
 * les cas importants : navigateur refusé, quota, requête invalide, réponse
 * normale, clé absente.
 *
 *   node relay/local-check.mjs
 */

import worker from './worker.js';

let failures = 0;

function check(label, condition, detail = '') {
  if (condition) {
    console.log(`  ok   ${label}`);
  } else {
    failures += 1;
    console.log(`  FAIL ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

/** D1 simulée : juste ce que le Worker utilise. */
function fakeDb() {
  const rows = new Map();
  return {
    rows,
    prepare(sql) {
      const statement = {
        args: [],
        bind(...args) {
          statement.args = args;
          return statement;
        },
        async first() {
          if (sql.includes('SELECT count')) {
            const [day, device] = statement.args;
            const count = rows.get(`${day}|${device}`);
            return count === undefined ? null : { count };
          }
          return null;
        },
        async run() {
          if (sql.includes('INSERT INTO usage')) {
            const [day, device] = statement.args;
            const key = `${day}|${device}`;
            rows.set(key, (rows.get(key) ?? 0) + 1);
          }
          return { success: true };
        },
      };
      return statement;
    },
  };
}

const DEVICE = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

function chatRequest(body, headers = {}) {
  return new Request('https://relay.test/v1/chat', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-device-id': DEVICE, ...headers },
    body: JSON.stringify(body),
  });
}

const okBody = { messages: [{ role: 'user', content: 'Bonjour' }] };

function groqReply(text = 'Salut !') {
  return {
    ok: true,
    status: 200,
    async json() {
      return { choices: [{ message: { role: 'assistant', content: text } }] };
    },
  };
}

const groqCalls = [];
const realFetch = globalThis.fetch;
globalThis.fetch = async (url, init) => {
  groqCalls.push({ url, body: JSON.parse(init.body) });
  return groqReply();
};

console.log('Relais WORLD-AI — vérification locale');

// 1. Santé : clé absente.
{
  const db = fakeDb();
  const response = await worker.fetch(
    new Request('https://relay.test/health'),
    { DB: db },
  );
  const body = await response.json();
  check('GET /health répond ok', response.status === 200 && body.ok === true);
  check('clé non configurée détectée', body.configured === false);
}

// 1 bis. Racine : page d'état lisible, pas une erreur JSON.
{
  const response = await worker.fetch(
    new Request('https://relay.test/'),
    { DB: fakeDb() },
  );
  const html = await response.text();
  check('GET / affiche une page d’état', response.status === 200 && html.includes('Relais WORLD-AI'));
  check('état de la clé visible', html.includes('Clé Groq manquante'));
  check('aucune clé divulgâchée', !html.toLowerCase().includes('gsk_'));
}

// 2. Appel venant d'un navigateur : refusé.
{
  const response = await worker.fetch(
    chatRequest(okBody, { origin: 'https://exemple.test' }),
    { DB: fakeDb(), GROQ_API_KEY: 'x' },
  );
  check('requête avec Origin refusée', response.status === 403);
}

// 3. Clé serveur absente : message clair, aucun appel sortant.
{
  groqCalls.length = 0;
  const response = await worker.fetch(chatRequest(okBody), { DB: fakeDb() });
  const body = await response.json();
  check('clé absente → 503', response.status === 503);
  check('clé absente → not_configured', body.error.code === 'not_configured');
  check('aucun appel à Groq', groqCalls.length === 0);
}

// 4. Requête invalide : refusée avant tout appel.
{
  groqCalls.length = 0;
  const empty = await worker.fetch(
    chatRequest({ messages: [] }),
    { DB: fakeDb(), GROQ_API_KEY: 'x' },
  );
  const noDevice = await worker.fetch(
    chatRequest(okBody, { 'x-device-id': '' }),
    { DB: fakeDb(), GROQ_API_KEY: 'x' },
  );
  check('historique vide → 400', empty.status === 400);
  check('appareil sans identifiant → 400', noDevice.status === 400);
  check('requêtes invalides sans appel sortant', groqCalls.length === 0);
}

// 5. Appel normal : réponse relayée et quota décompté.
{
  groqCalls.length = 0;
  const db = fakeDb();
  const response = await worker.fetch(chatRequest(okBody), {
    DB: db,
    GROQ_API_KEY: 'x',
  });
  const body = await response.json();
  check('réponse relayée', response.status === 200 && body.reply === 'Salut !');
  check('aucun quota annoncé', body.remaining === null, `remaining=${body.remaining}`);
  check('prompt système ajouté', groqCalls[0]?.body.messages[0].role === 'system');
  check('modèle par défaut', groqCalls[0]?.body.model === 'openai/gpt-oss-120b');
  check(
    'quota décrémenté',
    db.rows.get(`${new Date().toISOString().slice(0, 10)}|${DEVICE}`) === 1,
  );
}

// 6. Modèle hors liste : on retombe sur le modèle par défaut.
{
  groqCalls.length = 0;
  await worker.fetch(chatRequest({ ...okBody, model: 'autre/modele' }), {
    DB: fakeDb(),
    GROQ_API_KEY: 'x',
  });
  check('modèle inconnu ignoré', groqCalls[0]?.body.model === 'openai/gpt-oss-120b');
}

// 7. Aucune limite : un appareil déjà très actif passe encore.
{
  groqCalls.length = 0;
  const db = fakeDb();
  const day = new Date().toISOString().slice(0, 10);
  db.rows.set(`${day}|${DEVICE}`, 5000);
  db.rows.set(`${day}|global`, 50000);
  const response = await worker.fetch(chatRequest(okBody), {
    DB: db,
    GROQ_API_KEY: 'x',
  });
  const body = await response.json();
  check('gros usage → 200', response.status === 200);
  check('gros usage → réponse transmise', body.reply === 'Salut !');
  check('gros usage → aucun quota résiduel', body.remaining === null);
  check('gros usage → appel Groq effectué', groqCalls.length === 1);
  check('compteurs toujours incrémentés', db.rows.get(`${day}|${DEVICE}`) === 5001);
}

// 9. Mauvaise clé Groq : ne fuite rien.
{
  globalThis.fetch = async () => ({ ok: false, status: 401, async json() { return {}; } });
  const response = await worker.fetch(chatRequest(okBody), {
    DB: fakeDb(),
    GROQ_API_KEY: 'mauvaise',
  });
  const body = await response.json();
  check('clé invalide → 503', response.status === 503);
  check('message sans détail interne', body.error.message === 'La clé de l’IA est invalide.');
  globalThis.fetch = async (url, init) => {
    groqCalls.push({ url, body: JSON.parse(init.body) });
    return groqReply();
  };
}

globalThis.fetch = realFetch;

console.log(failures === 0 ? '\nTout est vert.' : `\n${failures} vérification(s) en échec.`);
process.exit(failures === 0 ? 0 : 1);
