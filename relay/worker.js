/**
 * Relais WORLD-AI → Groq.
 *
 * La clé Groq reste ici, dans un secret du Worker (GROQ_API_KEY) : elle n'est
 * jamais dans l'APK, ni dans le dépôt. L'application appelle ce Worker, qui
 * ajoute la clé et relaie la réponse.
 *
 * Garde-fous :
 *  - aucune requête venant d'un navigateur (en-tête Origin) n'est acceptée ;
 *  - les modèles sont limités à une liste fermée ;
 *  - usage compté anonymement dans D1, sans limite de messages.
 */

const GROQ_URL = 'https://api.groq.com/openai/v1/chat/completions';

// Tous les modèles de discussion Groq joignables avec la clé du projet et
// qui répondent en français. Whisper (audio), Orpheus (voix) et les garde-fous
// ne discutent pas ; les Llama 3.x et les modèles « Enterprise » demandent un
// contrat Groq et sont refusés pour cette clé.
const MODELS = new Set([
  'openai/gpt-oss-120b',
  'openai/gpt-oss-20b',
  'qwen/qwen3.8-27b',
]);
const DEFAULT_MODEL = 'openai/gpt-oss-120b';

const MAX_MESSAGES = 24;
const MAX_CONTENT_CHARS = 4000;
const MAX_COMPLETION_TOKENS = 1024;
// 0 = aucune limite. Les compteurs restent tenus à jour pour le suivi,
// mais ils ne bloquent plus jamais une requête.
const DEVICE_DAILY_LIMIT = 0;
const GLOBAL_DAILY_LIMIT = 0;

const SYSTEM_PROMPT =
  'Tu es WORLD-AI, un assistant francophone concis et utile. ' +
  'Réponds en français sauf si l’utilisateur écrit dans une autre langue. ' +
  'Reste bref, concret, et n’invente jamais une information.';

let schemaReady = false;

async function ensureSchema(db) {
  if (schemaReady) return;
  await db
    .prepare(
      'CREATE TABLE IF NOT EXISTS usage (' +
        'day TEXT NOT NULL, ' +
        'device TEXT NOT NULL, ' +
        'count INTEGER NOT NULL DEFAULT 0, ' +
        'PRIMARY KEY (day, device))',
    )
    .run();
  schemaReady = true;
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function fail(status, code, message) {
  return json({ error: { code, message } }, status);
}

/** Page d'état lisible : l'adresse n'est pas un site, mais elle ne doit pas
 * ressembler à une panne quand on l'ouvre dans un navigateur. */
function statusPage(configured) {
  const badge = configured
    ? '<span class="ok">Clé Groq configurée</span>'
    : '<span class="bad">Clé Groq manquante</span>';
  const hint = configured
    ? 'Le relais transmet les messages de l’application à Groq.'
    : 'Ajoute le secret <code>GROQ_API_KEY</code> dans l’onglet Secrets du projet pour activer les réponses.';

  return new Response(
    '<!doctype html><html lang="fr"><head><meta charset="utf-8">' +
      '<meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<title>Relais WORLD-AI</title><style>' +
      'body{margin:0;min-height:100vh;display:flex;align-items:center;' +
      'justify-content:center;background:#0b0912;color:#e9e6f5;' +
      'font:15px/1.6 system-ui,sans-serif;padding:24px}' +
      'main{max-width:460px}img{width:56px;height:56px;border-radius:18px;' +
      'background:linear-gradient(135deg,#7c5cff,#22d3ee);display:block;' +
      'margin-bottom:18px}h1{font-size:22px;margin:0 0 6px}' +
      'p{color:#a9a4c0;margin:0 0 16px}' +
      'span{display:inline-block;padding:6px 12px;border-radius:999px;' +
      'font-size:13px;font-weight:600}' +
      '.ok{background:#123a2b;color:#7ef0b0}.bad{background:#3a1c24;color:#f6a7b7}' +
      'code{background:#1b1730;padding:2px 6px;border-radius:6px;font-size:13px}' +
      'dl{margin:22px 0 0;font-size:13px;color:#8f8aa8}' +
      'dt{font-weight:600;color:#c9c4dd;margin-top:10px}dd{margin:2px 0 0}' +
      '</style></head><body><main>' +
      '<h1>Relais WORLD-AI</h1>' +
      '<p>Ce n’est pas le site WORLD-AI : cette adresse sert uniquement au ' +
      'fonctionnement de l’application.</p>' +
      badge +
      '<p style="margin-top:14px">' +
      hint +
      '</p>' +
      '<dl><dt>Point d’entrée</dt><dd><code>POST /v1/chat</code></dd>' +
      '<dt>Modèles</dt><dd>openai/gpt-oss-120b, openai/gpt-oss-20b, qwen/qwen3.8-27b</dd>' +
      '<dt>Quota</dt><dd>Aucune limite de messages</dd>' +
      '<dt>État</dt><dd><code>/health</code></dd></dl>' +
      '</main></body></html>',
    {
      status: 200,
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
      },
    },
  );
}

function today() {
  return new Date().toISOString().slice(0, 10);
}

async function readCount(db, day, device) {
  const row = await db
    .prepare('SELECT count FROM usage WHERE day = ? AND device = ?')
    .bind(day, device)
    .first();
  return row && typeof row.count === 'number' ? row.count : 0;
}

async function bump(db, day, device) {
  await db
    .prepare(
      'INSERT INTO usage (day, device, count) VALUES (?, ?, 1) ' +
        'ON CONFLICT(day, device) DO UPDATE SET count = count + 1',
    )
    .bind(day, device)
    .run();
}

/** Normalise et valide l'historique reçu depuis l'application. */
function readMessages(body) {
  if (!body || !Array.isArray(body.messages)) return null;
  if (body.messages.length === 0 || body.messages.length > MAX_MESSAGES) {
    return null;
  }
  const messages = [];
  for (const raw of body.messages) {
    if (!raw || typeof raw !== 'object') return null;
    const role = raw.role;
    const content = raw.content;
    if (role !== 'user' && role !== 'assistant') return null;
    if (typeof content !== 'string') return null;
    const trimmed = content.trim();
    if (trimmed.length === 0 || trimmed.length > MAX_CONTENT_CHARS) return null;
    messages.push({ role, content: trimmed });
  }
  if (messages[messages.length - 1].role !== 'user') return null;
  return messages;
}

async function relay(request, env) {
  const payload = await request.json().catch(() => null);
  const messages = readMessages(payload);
  if (!messages) {
    return fail(
      400,
      'bad_request',
      'Requête invalide : l’historique doit alterner des messages texte et se terminer par un message utilisateur.',
    );
  }

  const model =
    typeof payload.model === 'string' && MODELS.has(payload.model)
      ? payload.model
      : DEFAULT_MODEL;

  const rawDevice = request.headers.get('x-device-id') || '';
  const device = rawDevice.trim().toLowerCase();
  if (!/^[a-z0-9-]{16,64}$/.test(device)) {
    return fail(
      400,
      'bad_device',
      'Identifiant d’appareil manquant : mets à jour WORLD-AI.',
    );
  }

  if (!env.DB) {
    return fail(503, 'not_ready', 'Le service de quota n’est pas encore prêt.');
  }
  await ensureSchema(env.DB);

  const day = today();
  const [used, total] = await Promise.all([
    readCount(env.DB, day, device),
    readCount(env.DB, day, 'global'),
  ]);

  if (DEVICE_DAILY_LIMIT > 0 && used >= DEVICE_DAILY_LIMIT) {
    return fail(
      429,
      'device_limit',
      `Limite quotidienne atteinte (${DEVICE_DAILY_LIMIT} messages par appareil). Réessaie demain.`,
    );
  }
  if (GLOBAL_DAILY_LIMIT > 0 && total >= GLOBAL_DAILY_LIMIT) {
    return fail(
      429,
      'global_limit',
      'Le service a atteint son quota du jour. Réessaie demain.',
    );
  }

  if (!env.GROQ_API_KEY) {
    return fail(
      503,
      'not_configured',
      'L’IA n’est pas encore configurée côté serveur.',
    );
  }

  let upstream;
  try {
    upstream = await fetch(GROQ_URL, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${env.GROQ_API_KEY}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model,
        messages: [{ role: 'system', content: SYSTEM_PROMPT }, ...messages],
        max_completion_tokens: MAX_COMPLETION_TOKENS,
        temperature: 0.7,
      }),
    });
  } catch (error) {
    console.error('Groq injoignable', error);
    return fail(502, 'upstream', 'L’IA est momentanément injoignable.');
  }

  if (upstream.status === 401 || upstream.status === 403) {
    console.error('Clé Groq refusée', upstream.status);
    return fail(503, 'not_configured', 'La clé de l’IA est invalide.');
  }
  if (upstream.status === 429) {
    return fail(429, 'upstream_limit', 'L’IA est très sollicitée, réessaie dans un instant.');
  }
  if (!upstream.ok) {
    console.error('Groq a répondu', upstream.status);
    return fail(502, 'upstream', 'L’IA n’a pas pu répondre.');
  }

  const data = await upstream.json().catch(() => null);
  const text = data?.choices?.[0]?.message?.content;
  if (typeof text !== 'string' || text.trim().length === 0) {
    return fail(502, 'empty', 'Réponse vide de l’IA, réessaie.');
  }

  await Promise.all([bump(env.DB, day, device), bump(env.DB, day, 'global')]);

  const remaining =
    DEVICE_DAILY_LIMIT > 0
      ? Math.max(0, DEVICE_DAILY_LIMIT - (used + 1))
      : null;
  return json({ reply: text.trim(), model, remaining });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get('origin');
    if (origin !== null) {
      return fail(403, 'forbidden', 'Accès réservé à l’application WORLD-AI.');
    }

    if (url.pathname === '/') {
      return statusPage(Boolean(env.GROQ_API_KEY));
    }

    if (url.pathname === '/health') {
      return json({ ok: true, configured: Boolean(env.GROQ_API_KEY) });
    }

    if (url.pathname !== '/v1/chat') {
      return fail(404, 'not_found', 'Route inconnue.');
    }
    if (request.method !== 'POST') {
      return fail(405, 'method', 'Utilise POST.');
    }

    return relay(request, env);
  },
};
