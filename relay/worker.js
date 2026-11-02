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

// Comptes : mot de passe haché en PBKDF2-SHA256, jamais stocké en clair, et
// jetons de session gardés sous forme de condensat (le clair ne vit que dans
// l’application).
const PBKDF2_ITERATIONS = 100000;
const SESSION_DAYS = 90;
const MAX_FAILED_ATTEMPTS = 8;
const ATTEMPT_WINDOW_MS = 15 * 60 * 1000;
const MAX_EMAIL_CHARS = 190;
const MIN_PASSWORD_CHARS = 8;
const MAX_PASSWORD_CHARS = 200;

const MAX_CONVERSATIONS = 200;
const MAX_CONVERSATION_MESSAGES = 200;

let schemaReady = false;

async function ensureSchema(db) {
  if (schemaReady) return;
  await db.batch([
    db.prepare(
      'CREATE TABLE IF NOT EXISTS usage (' +
        'day TEXT NOT NULL, ' +
        'device TEXT NOT NULL, ' +
        'count INTEGER NOT NULL DEFAULT 0, ' +
        'PRIMARY KEY (day, device))',
    ),
    db.prepare(
      'CREATE TABLE IF NOT EXISTS users (' +
        'id TEXT PRIMARY KEY, ' +
        'email TEXT NOT NULL UNIQUE, ' +
        'hash TEXT NOT NULL, ' +
        'salt TEXT NOT NULL, ' +
        'iterations INTEGER NOT NULL, ' +
        'created_at INTEGER NOT NULL)',
    ),
    db.prepare(
      'CREATE TABLE IF NOT EXISTS sessions (' +
        'token TEXT PRIMARY KEY, ' +
        'user_id TEXT NOT NULL, ' +
        'created_at INTEGER NOT NULL, ' +
        'expires_at INTEGER NOT NULL)',
    ),
    db.prepare(
      'CREATE TABLE IF NOT EXISTS auth_attempts (' +
        'key TEXT PRIMARY KEY, ' +
        'count INTEGER NOT NULL DEFAULT 0, ' +
        'reset_at INTEGER NOT NULL)',
    ),
    db.prepare(
      'CREATE TABLE IF NOT EXISTS conversations (' +
        'id TEXT PRIMARY KEY, ' +
        'user_id TEXT NOT NULL, ' +
        'title TEXT NOT NULL DEFAULT "", ' +
        'created_at INTEGER NOT NULL, ' +
        'updated_at INTEGER NOT NULL)',
    ),
    db.prepare(
      'CREATE INDEX IF NOT EXISTS idx_conversations_user_updated ON conversations(user_id, updated_at DESC)',
    ),
    db.prepare(
      'CREATE TABLE IF NOT EXISTS messages (' +
        'id TEXT PRIMARY KEY, ' +
        'conversation_id TEXT NOT NULL, ' +
        'user_id TEXT NOT NULL, ' +
        'role TEXT NOT NULL, ' +
        'content TEXT NOT NULL, ' +
        'created_at INTEGER NOT NULL)',
    ),
    db.prepare(
      'CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, created_at ASC)',
    ),
    db.prepare(
      'CREATE INDEX IF NOT EXISTS idx_messages_user ON messages(user_id, created_at ASC)',
    ),
  ]);
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
      '<dl><dt>Discussion</dt><dd><code>POST /v1/chat</code></dd>' +
      '<dt>Comptes</dt><dd><code>POST /auth/register</code>, ' +
      '<code>POST /auth/login</code>, <code>GET /auth/me</code>, ' +
      '<code>POST /auth/logout</code></dd>' +
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

/* ------------------------------------------------------------------ comptes */

function toHex(bytes) {
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function fromHex(hex) {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i += 1) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function randomHex(size) {
  const bytes = new Uint8Array(size);
  crypto.getRandomValues(bytes);
  return toHex(bytes);
}

function randomToken() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

async function sha256(text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return toHex(new Uint8Array(digest));
}

async function hashPassword(password, saltHex, iterations) {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: fromHex(saltHex), iterations, hash: 'SHA-256' },
    key,
    256,
  );
  return toHex(new Uint8Array(bits));
}

/** Comparaison à temps constant, pour ne pas fuiter le condensat par timing. */
function sameHash(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Normalise l’adresse : minuscules, sans espaces autour. */
function normalizeEmail(value) {
  if (typeof value !== 'string') return null;
  const email = value.trim().toLowerCase();
  if (email.length < 5 || email.length > MAX_EMAIL_CHARS) return null;
  if (!/^[^\s@]+@[^\s@]+\.[a-z]{2,}$/.test(email)) return null;
  return email;
}

function readPassword(value) {
  if (typeof value !== 'string') return null;
  if (value.length < MIN_PASSWORD_CHARS || value.length > MAX_PASSWORD_CHARS) {
    return null;
  }
  return value;
}

function clientKey(request) {
  const ip =
    request.headers.get('cf-connecting-ip') ||
    request.headers.get('x-forwarded-for') ||
    'inconnu';
  return ip.split(',')[0].trim().slice(0, 64);
}

/** Bloque les essais en série sur un même compte ou une même adresse IP. */
async function attemptsLeft(db, key) {
  const row = await db
    .prepare('SELECT count, reset_at FROM auth_attempts WHERE key = ?')
    .bind(key)
    .first();
  if (!row || row.reset_at <= Date.now()) return MAX_FAILED_ATTEMPTS;
  return Math.max(0, MAX_FAILED_ATTEMPTS - row.count);
}

async function noteFailure(db, key) {
  const resetAt = Date.now() + ATTEMPT_WINDOW_MS;
  await db
    .prepare(
      'INSERT INTO auth_attempts (key, count, reset_at) VALUES (?, 1, ?) ' +
        'ON CONFLICT(key) DO UPDATE SET count = count + 1, reset_at = excluded.reset_at',
    )
    .bind(key, resetAt)
    .run();
}

async function clearFailures(db, key) {
  await db.prepare('DELETE FROM auth_attempts WHERE key = ?').bind(key).run();
}

function publicUser(row) {
  return { id: row.id, email: row.email, createdAt: row.created_at };
}

/** Ouvre une session et renvoie le jeton en clair, à usage unique côté app. */
async function openSession(db, userId) {
  const token = randomToken();
  const now = Date.now();
  await db
    .prepare(
      'INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
    )
    .bind(await sha256(token), userId, now, now + SESSION_DAYS * 86400000)
    .run();
  return token;
}

/** Retrouve le compte derrière un en-tête Authorization: Bearer … */
async function currentUser(request, db) {
  const header = request.headers.get('authorization') || '';
  const match = /^Bearer\s+([A-Za-z0-9_-]{20,128})$/.exec(header.trim());
  if (!match) return null;
  const session = await db
    .prepare('SELECT user_id, expires_at FROM sessions WHERE token = ?')
    .bind(await sha256(match[1]))
    .first();
  if (!session || session.expires_at <= Date.now()) return null;
  const user = await db
    .prepare('SELECT id, email, created_at FROM users WHERE id = ?')
    .bind(session.user_id)
    .first();
  return user || null;
}

function uid() {
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i].toString(16).padStart(2, '0');
  }
  return out;
}

function trimTitle(text) {
  const s = String(text || '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!s) return 'Nouvelle discussion';
  return s.length > 40 ? s.slice(0, 40) + '…' : s;
}

async function ensureOwnConversation(db, userId, conversationId) {
  const row = await db
    .prepare('SELECT id, user_id, title, created_at, updated_at FROM conversations WHERE id = ?1')
    .bind(conversationId)
    .first();
  if (!row || row.user_id !== userId) return null;
  return row;
}

async function listConversations(db, userId) {
  const { results } = await db
    .prepare(
      'SELECT id, title, created_at, updated_at FROM conversations WHERE user_id = ?1 ORDER BY updated_at DESC LIMIT ?2',
    )
    .bind(userId, MAX_CONVERSATIONS)
    .all();
  return results || [];
}

async function getConversationMessages(db, conversationId) {
  const { results } = await db
    .prepare(
      'SELECT id, role, content, created_at FROM messages WHERE conversation_id = ?1 ORDER BY created_at ASC LIMIT ?2',
    )
    .bind(conversationId, MAX_CONVERSATION_MESSAGES)
    .all();
  return results || [];
}

async function readAuthBody(request) {
  return request.json().catch(() => null);
}

async function register(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);

  const body = await readAuthBody(request);
  const email = normalizeEmail(body?.email);
  const password = readPassword(body?.password);
  if (!email) {
    return fail(400, 'bad_email', 'Adresse e-mail invalide.');
  }
  if (!password) {
    return fail(
      400,
      'bad_password',
      `Le mot de passe doit faire entre ${MIN_PASSWORD_CHARS} et ${MAX_PASSWORD_CHARS} caractères.`,
    );
  }

  const key = `reg:${clientKey(request)}`;
  if ((await attemptsLeft(env.DB, key)) === 0) {
    return fail(429, 'too_many', 'Trop de tentatives. Réessaie dans un quart d’heure.');
  }
  await noteFailure(env.DB, key);

  const existing = await env.DB
    .prepare('SELECT id FROM users WHERE email = ?')
    .bind(email)
    .first();
  if (existing) {
    return fail(409, 'email_taken', 'Un compte existe déjà avec cette adresse.');
  }

  const id = randomHex(12);
  const salt = randomHex(16);
  const hash = await hashPassword(password, salt, PBKDF2_ITERATIONS);
  await env.DB
    .prepare(
      'INSERT INTO users (id, email, hash, salt, iterations, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    )
    .bind(id, email, hash, salt, PBKDF2_ITERATIONS, Date.now())
    .run();

  const token = await openSession(env.DB, id);
  return json(
    { token, user: { id, email, createdAt: Date.now() } },
    201,
  );
}

async function login(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);

  const body = await readAuthBody(request);
  const email = normalizeEmail(body?.email);
  const password = readPassword(body?.password);
  if (!email || !password) {
    return fail(401, 'invalid_credentials', 'Adresse ou mot de passe incorrect.');
  }

  const key = `login:${clientKey(request)}:${email}`;
  if ((await attemptsLeft(env.DB, key)) === 0) {
    return fail(
      429,
      'too_many',
      'Trop de tentatives. Réessaie dans un quart d’heure.',
    );
  }

  const user = await env.DB
    .prepare('SELECT id, email, hash, salt, iterations, created_at FROM users WHERE email = ?')
    .bind(email)
    .first();

  // Même délai et même message quand le compte n’existe pas : on ne révèle
  // pas quelles adresses sont inscrites.
  const salt = user ? user.salt : randomHex(16);
  const iterations = user ? user.iterations : PBKDF2_ITERATIONS;
  const candidate = await hashPassword(password, salt, iterations);
  if (!user || !sameHash(candidate, user.hash)) {
    await noteFailure(env.DB, key);
    return fail(401, 'invalid_credentials', 'Adresse ou mot de passe incorrect.');
  }

  await clearFailures(env.DB, key);
  const token = await openSession(env.DB, user.id);
  return json({ token, user: publicUser(user) });
}

async function me(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);
  const user = await currentUser(request, env.DB);
  if (!user) return fail(401, 'signed_out', 'Session expirée. Reconnecte-toi.');
  return json({ user: publicUser(user) });
}

async function logout(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);
  const header = request.headers.get('authorization') || '';
  const match = /^Bearer\s+([A-Za-z0-9_-]{20,128})$/.exec(header.trim());
  if (match) {
    await env.DB
      .prepare('DELETE FROM sessions WHERE token = ?')
      .bind(await sha256(match[1]))
      .run();
  }
  return json({ ok: true });
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

async function listConversationsRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);
  const user = await currentUser(request, env.DB);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const items = await listConversations(env.DB, user.id);
  return json({ conversations: items });
}

async function createConversationRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);
  const user = await currentUser(request, env.DB);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const body = await request.json().catch(() => ({}));
  const title = trimTitle(body?.title);
  const now = Date.now();
  const id = uid();
  await env.DB
    .prepare(
      'INSERT INTO conversations (id, user_id, title, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
    )
    .bind(id, user.id, title, now, now)
    .run();
  return json({ conversation: { id, title, created_at: now, updated_at: now } }, 201);
}

async function getConversationRoute(request, env, conversationId) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);
  const user = await currentUser(request, env.DB);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const conv = await ensureOwnConversation(env.DB, user.id, conversationId);
  if (!conv) return fail(404, 'not_found', 'Discussion introuvable.');
  const messages = await getConversationMessages(env.DB, conversationId);
  return json({ conversation: conv, messages });
}

async function updateConversationRoute(request, env, conversationId) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);
  const user = await currentUser(request, env.DB);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const conv = await ensureOwnConversation(env.DB, user.id, conversationId);
  if (!conv) return fail(404, 'not_found', 'Discussion introuvable.');
  const body = await request.json().catch(() => ({}));
  const title = trimTitle(body?.title);
  const now = Date.now();
  await env.DB
    .prepare('UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?')
    .bind(title, now, conversationId)
    .run();
  return json({ conversation: { ...conv, title, updated_at: now } });
}

async function deleteConversationRoute(request, env, conversationId) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);
  const user = await currentUser(request, env.DB);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const conv = await ensureOwnConversation(env.DB, user.id, conversationId);
  if (!conv) return fail(404, 'not_found', 'Discussion introuvable.');
  await env.DB.batch([
    env.DB.prepare('DELETE FROM messages WHERE conversation_id = ?').bind(conversationId),
    env.DB.prepare('DELETE FROM conversations WHERE id = ?').bind(conversationId),
  ]);
  return json({ ok: true });
}

async function getMessagesRoute(request, env, conversationId) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);
  const user = await currentUser(request, env.DB);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const conv = await ensureOwnConversation(env.DB, user.id, conversationId);
  if (!conv) return fail(404, 'not_found', 'Discussion introuvable.');
  const messages = await getConversationMessages(env.DB, conversationId);
  return json({ messages });
}

async function appendMessagesRoute(request, env, conversationId) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  await ensureSchema(env.DB);
  const user = await currentUser(request, env.DB);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const conv = await ensureOwnConversation(env.DB, user.id, conversationId);
  if (!conv) return fail(404, 'not_found', 'Discussion introuvable.');
  const body = await request.json().catch(() => ({}));
  const items = Array.isArray(body?.messages) ? body.messages : [];
  if (items.length === 0) return json({ ok: true });
  const now = Date.now();
  const stmts = [];
  for (const item of items) {
    const role = item?.role === 'assistant' ? 'assistant' : 'user';
    const content = String(item?.content || '').trim();
    if (!content) continue;
    if (content.length > MAX_CONTENT_CHARS) continue;
    stmts.push(
      env.DB
        .prepare(
          'INSERT INTO messages (id, conversation_id, user_id, role, content, created_at) VALUES (?, ?, ?, ?, ?, ?)',
        )
        .bind(uid(), conversationId, user.id, role, content, item?.created_at || now),
    );
  }
  if (stmts.length === 0) return json({ ok: true });
  stmts.push(
    env.DB
      .prepare('UPDATE conversations SET updated_at = ? WHERE id = ?')
      .bind(now, conversationId),
  );
  await env.DB.batch(stmts);
  return json({ ok: true });
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

    if (url.pathname === '/auth/register') {
      if (request.method !== 'POST') return fail(405, 'method', 'Utilise POST.');
      return register(request, env);
    }

    if (url.pathname === '/auth/login') {
      if (request.method !== 'POST') return fail(405, 'method', 'Utilise POST.');
      return login(request, env);
    }

    if (url.pathname === '/auth/me') {
      if (request.method !== 'GET') return fail(405, 'method', 'Utilise GET.');
      return me(request, env);
    }

    if (url.pathname === '/auth/logout') {
      if (request.method !== 'POST') return fail(405, 'method', 'Utilise POST.');
      return logout(request, env);
    }

    if (url.pathname === '/conversations') {
      if (request.method === 'GET') return listConversationsRoute(request, env);
      if (request.method === 'POST') return createConversationRoute(request, env);
      return fail(405, 'method', 'Utilise GET ou POST.');
    }

    if (url.pathname.startsWith('/conversations/')) {
      const parts = url.pathname.split('/').filter(Boolean);
      if (parts.length === 2) {
        if (request.method === 'GET') return getConversationRoute(request, env, parts[1]);
        if (request.method === 'DELETE') return deleteConversationRoute(request, env, parts[1]);
        if (request.method === 'PATCH' || request.method === 'PUT')
          return updateConversationRoute(request, env, parts[1]);
        return fail(405, 'method', 'Utilise GET, PATCH ou DELETE.');
      }
      if (parts.length === 3 && parts[2] === 'messages') {
        if (request.method === 'GET') return getMessagesRoute(request, env, parts[1]);
        if (request.method === 'POST') return appendMessagesRoute(request, env, parts[1]);
        return fail(405, 'method', 'Utilise GET ou POST.');
      }
      return fail(404, 'not_found', 'Route inconnue.');
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
