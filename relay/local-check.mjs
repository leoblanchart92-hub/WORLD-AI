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

/** D1 simulée : juste ce que le Worker utilise (usage, comptes, sessions). */
function fakeDb() {
  const rows = new Map();
  const users = new Map();
  const sessions = new Map();
  const attempts = new Map();
  const sites = new Map();

  return {
    rows,
    users,
    sessions,
    attempts,
    sites,
    async batch(statements) {
      return Promise.all(statements.map((statement) => statement.run()));
    },
    prepare(sql) {
      const statement = {
        args: [],
        bind(...args) {
          statement.args = args;
          return statement;
        },
        async first() {
          if (sql.startsWith('SELECT count FROM usage')) {
            const [day, device] = statement.args;
            const count = rows.get(`${day}|${device}`);
            return count === undefined ? null : { count };
          }
          if (sql.startsWith('SELECT id FROM users WHERE email')) {
            return users.get(statement.args[0]) ?? null;
          }
          if (sql.startsWith('SELECT id, email, hash, salt')) {
            return users.get(statement.args[0]) ?? null;
          }
          if (sql.startsWith('SELECT id, email, created_at FROM users')) {
            const found = [...users.values()].find((user) => user.id === statement.args[0]);
            return found ?? null;
          }
          if (sql.startsWith('SELECT user_id, expires_at FROM sessions')) {
            return sessions.get(statement.args[0]) ?? null;
          }
          if (sql.startsWith('SELECT count, reset_at FROM auth_attempts')) {
            return attempts.get(statement.args[0]) ?? null;
          }
          if (sql.startsWith('SELECT html FROM sites')) {
            const site = sites.get(statement.args[0]);
            return site ? { html: site.html } : null;
          }
          if (sql.startsWith('SELECT title FROM sites')) {
            const site = sites.get(statement.args[0]);
            if (!site || site.user_id !== statement.args[1]) return null;
            return { title: site.title };
          }
          if (sql.startsWith('SELECT COUNT(*) AS total FROM sites')) {
            const total = [...sites.values()].filter((s) => s.user_id === statement.args[0]).length;
            return { total };
          }
          return null;
        },
        async all() {
          if (sql.startsWith('SELECT slug, title, updated_at FROM sites')) {
            const results = [...sites.values()]
              .filter((s) => s.user_id === statement.args[0])
              .sort((a, b) => b.updated_at - a.updated_at)
              .map((s) => ({ slug: s.slug, title: s.title, updated_at: s.updated_at }));
            return { results };
          }
          return { results: [] };
        },
        async run() {
          if (sql.startsWith('INSERT INTO usage')) {
            const [day, device] = statement.args;
            const key = `${day}|${device}`;
            rows.set(key, (rows.get(key) ?? 0) + 1);
          } else if (sql.startsWith('INSERT INTO users')) {
            const [id, email, hash, salt, iterations, createdAt] = statement.args;
            users.set(email, { id, email, hash, salt, iterations, created_at: createdAt });
          } else if (sql.startsWith('INSERT INTO sessions')) {
            const [token, userId, createdAt, expiresAt] = statement.args;
            sessions.set(token, { user_id: userId, created_at: createdAt, expires_at: expiresAt });
          } else if (sql.startsWith('DELETE FROM sessions')) {
            sessions.delete(statement.args[0]);
          } else if (sql.startsWith('INSERT INTO auth_attempts')) {
            const [key, resetAt] = statement.args;
            const current = attempts.get(key);
            attempts.set(key, {
              count: (current?.count ?? 0) + 1,
              reset_at: resetAt,
            });
          } else if (sql.startsWith('DELETE FROM auth_attempts')) {
            attempts.delete(statement.args[0]);
          } else if (sql.startsWith('INSERT INTO sites')) {
            const [slug, userId, title, html, createdAt, updatedAt] = statement.args;
            sites.set(slug, {
              slug,
              user_id: userId,
              title,
              html,
              created_at: createdAt,
              updated_at: updatedAt,
            });
          } else if (sql.startsWith('UPDATE sites')) {
            const [title, html, updatedAt, slug, userId] = statement.args;
            const site = sites.get(slug);
            if (site && site.user_id === userId) {
              site.title = title;
              site.html = html;
              site.updated_at = updatedAt;
            }
          } else if (sql.startsWith('DELETE FROM sites')) {
            const [slug, userId] = statement.args;
            const site = sites.get(slug);
            if (site && site.user_id === userId) sites.delete(slug);
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

function authRequest(path, body, headers = {}) {
  return new Request(`https://relay.test${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    headers: {
      'content-type': 'application/json',
      'cf-connecting-ip': '203.0.113.7',
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

// 8. Comptes : inscription, connexion, session, déconnexion.
{
  const db = fakeDb();
  const env = { DB: db };

  const created = await worker.fetch(
    authRequest('/auth/register', { email: ' Leo@Exemple.FR ', password: 'motdepasse123' }),
    env,
  );
  const createdBody = await created.json();
  check('inscription → 201', created.status === 201, `status=${created.status}`);
  check('adresse normalisée', createdBody.user?.email === 'leo@exemple.fr');
  check(
    'jeton de session remis',
    typeof createdBody.token === 'string' && createdBody.token.length >= 32,
  );
  const stored = db.users.get('leo@exemple.fr');
  check(
    'mot de passe jamais stocké en clair',
    Boolean(stored) &&
      stored.hash !== 'motdepasse123' &&
      !JSON.stringify(stored).includes('motdepasse123'),
  );

  const duplicate = await worker.fetch(
    authRequest('/auth/register', { email: 'leo@exemple.fr', password: 'motdepasse123' }),
    env,
  );
  check('adresse déjà prise → 409', duplicate.status === 409);

  const wrong = await worker.fetch(
    authRequest('/auth/login', { email: 'leo@exemple.fr', password: 'mauvaispass' }),
    env,
  );
  check('mauvais mot de passe → 401', wrong.status === 401);
  check('aucun détail sur le compte', (await wrong.json()).error.code === 'invalid_credentials');

  const ok = await worker.fetch(
    authRequest('/auth/login', { email: 'leo@exemple.fr', password: 'motdepasse123' }),
    env,
  );
  const okBody = await ok.json();
  check('connexion → 200', ok.status === 200);
  check('connexion → jeton', typeof okBody.token === 'string');

  const meRes = await worker.fetch(
    authRequest('/auth/me', undefined, { authorization: `Bearer ${okBody.token}` }),
    env,
  );
  const meBody = await meRes.json();
  check(
    'session valide → /auth/me',
    meRes.status === 200 && meBody.user.email === 'leo@exemple.fr',
  );

  const anon = await worker.fetch(authRequest('/auth/me'), env);
  check('sans jeton → 401', anon.status === 401);

  const bad = await worker.fetch(
    authRequest('/auth/me', undefined, { authorization: 'Bearer nimportequoi' }),
    env,
  );
  check('jeton invalide → 401', bad.status === 401);

  await worker.fetch(
    authRequest('/auth/logout', {}, { authorization: `Bearer ${okBody.token}` }),
    env,
  );
  const after = await worker.fetch(
    authRequest('/auth/me', undefined, { authorization: `Bearer ${okBody.token}` }),
    env,
  );
  check('déconnexion → session fermée', after.status === 401);

  const short = await worker.fetch(
    authRequest('/auth/register', { email: 'b@exemple.fr', password: 'court' }),
    env,
  );
  check('mot de passe trop court → 400', short.status === 400);
  const badEmail = await worker.fetch(
    authRequest('/auth/register', { email: 'pas-une-adresse', password: 'motdepasse123' }),
    env,
  );
  check('adresse invalide → 400', badEmail.status === 400);

  const browser = await worker.fetch(
    authRequest('/auth/login', { email: 'leo@exemple.fr', password: 'motdepasse123' }, { origin: 'https://exemple.test' }),
    env,
  );
  check('navigateur refusé aussi sur /auth', browser.status === 403);
}

// 8 bis. Force brute : bloquée après huit échecs.
{
  const db = fakeDb();
  const env = { DB: db };
  await worker.fetch(
    authRequest('/auth/register', { email: 'brute@exemple.fr', password: 'motdepasse123' }),
    env,
  );
  let last;
  for (let attempt = 0; attempt < 9; attempt += 1) {
    last = await worker.fetch(
      authRequest('/auth/login', { email: 'brute@exemple.fr', password: 'fauxmdp12345' }),
      env,
    );
  }
  check('force brute → 429', last.status === 429, `status=${last.status}`);
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

// 10. Sites de test : publication, lecture publique, propriété, suppression.
{
  const db = fakeDb();
  const env = { DB: db };
  const created = await worker.fetch(
    authRequest('/auth/register', { email: 'site@exemple.fr', password: 'motdepasse123' }),
    env,
  );
  const { token } = await created.json();
  const auth = { authorization: `Bearer ${token}` };

  const anon = await worker.fetch(authRequest('/sites', { html: '<h1>test</h1>' }), env);
  check('site sans compte → 401', anon.status === 401);

  const made = await worker.fetch(
    authRequest('/sites', { title: 'Démo', html: '<!doctype html><h1>Salut</h1>' }, auth),
    env,
  );
  const madeBody = await made.json();
  check('création de site → 201/200', made.status === 200, `status=${made.status}`);
  const slug = madeBody.site?.slug;
  check('création → slug', typeof slug === 'string' && /^[a-f0-9]{18}$/.test(slug));
  check(
    'création → adresse publique',
    madeBody.site?.url === `https://relay.test/s/${slug}`,
    madeBody.site?.url,
  );

  const page = await worker.fetch(new Request(`https://relay.test/s/${slug}`), env);
  const pageBody = await page.text();
  check('page publique → 200', page.status === 200, `status=${page.status}`);
  check('page publique → HTML servi', pageBody.includes('<h1>Salut</h1>'));
  check(
    'page publique → sandbox',
    (page.headers.get('content-security-policy') || '').includes('sandbox'),
  );
  check(
    'page publique → type HTML',
    (page.headers.get('content-type') || '').startsWith('text/html'),
  );

  const unknown = await worker.fetch(new Request('https://relay.test/s/000000000000000000'), env);
  check('site inconnu → 404', unknown.status === 404);
  const invalid = await worker.fetch(new Request('https://relay.test/s/pas-un-slug'), env);
  check('slug invalide → 404', invalid.status === 404);

  const listed = await worker.fetch(authRequest('/sites', undefined, auth), env);
  const listedBody = await listed.json();
  check(
    'liste des sites → 1 entrée',
    listed.status === 200 && listedBody.sites?.length === 1,
    `status=${listed.status}`,
  );

  const other = await worker.fetch(
    authRequest('/auth/register', { email: 'autre@exemple.fr', password: 'motdepasse123' }),
    env,
  );
  const otherToken = (await other.json()).token;
  const foreignDelete = await worker.fetch(
    new Request(`https://relay.test/sites/${slug}`, {
      method: 'DELETE',
      headers: { authorization: `Bearer ${otherToken}` },
    }),
    env,
  );
  check('suppression par un autre compte → 404', foreignDelete.status === 404);
  check('site toujours là', db.sites.size === 1);

  const emptied = await worker.fetch(
    authRequest('/sites', { title: '', html: '   ' }, auth),
    env,
  );
  check('contenu vide → 400', emptied.status === 400);

  const removed = await worker.fetch(
    new Request(`https://relay.test/sites/${slug}`, { method: 'DELETE', headers: auth }),
    env,
  );
  check('suppression par le propriétaire', removed.status === 200);
  check('site retiré de la base', db.sites.size === 0);
  const gone = await worker.fetch(new Request(`https://relay.test/s/${slug}`), env);
  check('adresse supprimée → 404', gone.status === 404);
}

// 11. L’IA publie un site quand on lui demande.
{
  const db = fakeDb();
  const env = { DB: db, GROQ_API_KEY: 'cle-de-test' };
  const created = await worker.fetch(
    authRequest('/auth/register', { email: 'outil@exemple.fr', password: 'motdepasse123' }),
    env,
  );
  const { token } = await created.json();

  let call = 0;
  globalThis.fetch = async () => {
    call += 1;
    const message =
      call === 1
        ? {
            role: 'assistant',
            content: '',
            tool_calls: [
              {
                id: 'appel-1',
                type: 'function',
                function: {
                  name: 'site_create',
                  arguments: JSON.stringify({
                    title: 'Page de test',
                    html: '<!doctype html><h1>Page de test</h1>',
                  }),
                },
              },
            ],
          }
        : { role: 'assistant', content: 'Le site est publié.' };
    return {
      ok: true,
      status: 200,
      async json() {
        return { choices: [{ message }] };
      },
    };
  };

  const answer = await worker.fetch(
    chatRequest({ messages: [{ role: 'user', content: 'crée un site de test' }] }, {
      authorization: `Bearer ${token}`,
    }),
    env,
  );
  const answerBody = await answer.json();
  check(
    'chat → outil site_create exécuté',
    Array.isArray(answerBody.actions) &&
      answerBody.actions.some((action) => action.tool === 'site_create' && action.ok),
    JSON.stringify(answerBody.actions),
  );
  check('chat → site écrit en base', db.sites.size === 1);
  check('chat → réponse finale', answerBody.reply === 'Le site est publié.');
}

globalThis.fetch = realFetch;

console.log(failures === 0 ? '\nTout est vert.' : `\n${failures} vérification(s) en échec.`);
process.exit(failures === 0 ? 0 : 1);
