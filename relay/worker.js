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

// ---------------------------------------------------------------- GitHub
// Le jeton GitHub vit dans le secret GITHUB_TOKEN du Worker. Il n'est jamais
// renvoyé au client : seul l'état des actions remonte dans la réponse.
const GITHUB_API = 'https://api.github.com';
// Connexion OAuth « device flow » : chaque personne relie son propre compte
// GitHub, et le jeton obtenu reste dans la base du relais — jamais dans
// l'application, jamais dans la réponse.
const GITHUB_DEVICE_CODE_URL = 'https://github.com/login/device/code';
const GITHUB_ACCESS_TOKEN_URL = 'https://github.com/login/oauth/access_token';
const GITHUB_SCOPES = 'repo workflow read:user';
const DEFAULT_GITHUB_REPO = 'leoblanchart92-hub/WORLD-AI';
const MAX_TOOL_STEPS = 6;
const MAX_TOOL_RESULT_CHARS = 12000;
const MAX_WRITE_FILES = 12;
const MAX_FILE_CONTENT_CHARS = 200000;

// Sites de test publiés par l’IA : une page HTML autonome par site.
const MAX_SITES_PER_USER = 50;
const MAX_SITE_HTML_CHARS = 300000;
const SITE_SLUG_RE = /^[a-f0-9]{8,64}$/;

const MAX_MESSAGES = 24;
const MAX_CONTENT_CHARS = 4000;
const MAX_ATTACHMENT_CHARS = 8000;
const MAX_ATTACHMENTS = 4;
const MAX_ATTACHMENT_BYTES = 5 * 1024 * 1024;
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
    db.prepare(
      'CREATE TABLE IF NOT EXISTS github_accounts (' +
        'user_id TEXT PRIMARY KEY, ' +
        'login TEXT NOT NULL, ' +
        'token TEXT NOT NULL, ' +
        'scopes TEXT NOT NULL DEFAULT "", ' +
        'default_repo TEXT NOT NULL DEFAULT "", ' +
        'created_at INTEGER NOT NULL, ' +
        'updated_at INTEGER NOT NULL)',
    ),
    db.prepare(
      'CREATE TABLE IF NOT EXISTS github_pending (' +
        'id TEXT PRIMARY KEY, ' +
        'user_id TEXT NOT NULL, ' +
        'device_code TEXT NOT NULL, ' +
        'interval INTEGER NOT NULL, ' +
        'expires_at INTEGER NOT NULL, ' +
        'created_at INTEGER NOT NULL)',
    ),
    db.prepare(
      'CREATE TABLE IF NOT EXISTS sites (' +
        'slug TEXT PRIMARY KEY, ' +
        'user_id TEXT NOT NULL, ' +
        'title TEXT NOT NULL DEFAULT "", ' +
        'html TEXT NOT NULL, ' +
        'created_at INTEGER NOT NULL, ' +
        'updated_at INTEGER NOT NULL)',
    ),
    db.prepare(
      'CREATE INDEX IF NOT EXISTS idx_sites_user ON sites(user_id, updated_at DESC)',
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
function statusPage(configured, github = false) {
  const badge = configured
    ? '<span class="ok">Clé Groq configurée</span>'
    : '<span class="bad">Clé Groq manquante</span>';
  const githubBadge = github
    ? '<span class="ok">GitHub connecté</span>'
    : '<span class="bad">GitHub non connecté</span>';
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
      ' ' +
      githubBadge +
      '<p style="margin-top:14px">' +
      hint +
      '</p>' +
      '<dl><dt>Discussion</dt><dd><code>POST /v1/chat</code></dd>' +
      '<dt>Comptes</dt><dd><code>POST /auth/register</code>, ' +
      '<code>POST /auth/login</code>, <code>GET /auth/me</code>, ' +
      '<code>POST /auth/logout</code></dd>' +
      '<dt>Sites de test</dt><dd><code>GET /s/&lt;slug&gt;</code>, ' +
      '<code>GET /sites</code>, <code>POST /sites</code></dd>' +
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

function isImageMime(mime) {
  return typeof mime === 'string' && mime.startsWith('image/');
}

function isTextLikeMime(mime) {
  if (typeof mime !== 'string') return false;
  if (mime.startsWith('text/')) return true;
  if (mime === 'application/json') return true;
  if (mime === 'application/xml') return true;
  if (mime === 'application/javascript') return true;
  if (mime === 'application/typescript') return true;
  return false;
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
    messages.push({ role, content: trimmed, attachments: Array.isArray(raw.attachments) ? raw.attachments : [] });
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

/* ---------------------------------------------------------------- GitHub */

function functionTool(name, description, properties, required) {
  return {
    type: 'function',
    function: {
      name,
      description,
      parameters: {
        type: 'object',
        properties,
        required,
        additionalProperties: false,
      },
    },
  };
}

function tool(name, description, properties = {}, required = []) {
  return functionTool(
    name,
    description,
    {
      repo: S('Dépôt visé, « propriétaire/nom ». Omets-le pour utiliser le dépôt courant.'),
      ...properties,
    },
    required,
  );
}

/** Outil qui ne parle pas à GitHub : pas d’argument « repo » implicite. */
function siteTool(name, description, properties = {}, required = []) {
  return functionTool(name, description, properties, required);
}

const S = (description) => ({ type: 'string', description });
const N = (description) => ({ type: 'number', description });
const B = (description) => ({ type: 'boolean', description });

const GITHUB_TOOLS = [
  tool('github_list_repos', 'Liste les dépôts du compte GitHub connecté, du plus récemment modifié au plus ancien.', {
    limit: N('Nombre maximum (défaut 30).'),
  }),
  tool('github_repo_info', 'Décrit le dépôt GitHub configuré : branche par défaut, langage, nombres d’issues et d’étoiles.', {}),
  tool('github_list_files', 'Liste l’arborescence des fichiers du dépôt.', {
    path: S('Dossier de départ, vide pour la racine.'),
    branch: S('Branche (défaut : branche par défaut du dépôt).'),
    limit: N('Nombre maximum de chemins renvoyés (défaut 200).'),
  }),
  tool('github_read_file', 'Lit le contenu texte d’un fichier du dépôt.', {
    path: S('Chemin du fichier dans le dépôt.'),
    branch: S('Branche (défaut : branche par défaut).'),
  }, ['path']),
  tool('github_search_code', 'Cherche du texte dans le code du dépôt.', {
    query: S('Texte ou motif à chercher.'),
    limit: N('Nombre maximum de résultats (défaut 20).'),
  }, ['query']),
  tool('github_list_branches', 'Liste les branches du dépôt.', {}),
  tool('github_list_commits', 'Liste les derniers commits.', {
    limit: N('Nombre de commits (défaut 15).'),
    path: S('Limiter à un fichier ou dossier.'),
    branch: S('Branche.'),
  }),
  tool('github_list_issues', 'Liste les issues (et pull requests) du dépôt.', {
    state: S('open, closed ou all (défaut open).'),
    limit: N('Nombre maximum (défaut 20).'),
  }),
  tool('github_get_issue', 'Lit une issue avec ses commentaires.', {
    number: N('Numéro de l’issue.'),
  }, ['number']),
  tool('github_create_issue', 'Ouvre une nouvelle issue.', {
    title: S('Titre de l’issue.'),
    body: S('Description en Markdown.'),
    labels: { type: 'array', items: { type: 'string' }, description: 'Étiquettes à poser.' },
  }, ['title']),
  tool('github_comment_issue', 'Ajoute un commentaire à une issue ou une pull request.', {
    number: N('Numéro de l’issue ou de la PR.'),
    body: S('Commentaire en Markdown.'),
  }, ['number', 'body']),
  tool('github_set_issue_state', 'Ferme ou rouvre une issue.', {
    number: N('Numéro de l’issue.'),
    state: S('closed ou open.'),
  }, ['number', 'state']),
  tool('github_list_pulls', 'Liste les pull requests.', {
    state: S('open, closed ou all (défaut open).'),
    limit: N('Nombre maximum (défaut 20).'),
  }),
  tool('github_get_pull', 'Lit une pull request avec ses fichiers modifiés.', {
    number: N('Numéro de la pull request.'),
  }, ['number']),
  tool('github_create_pull', 'Ouvre une pull request depuis une branche existante.', {
    title: S('Titre de la pull request.'),
    head: S('Branche source (celle qui contient les changements).'),
    base: S('Branche cible (défaut : branche par défaut).'),
    body: S('Description en Markdown.'),
    draft: B('Ouvrir en brouillon.'),
  }, ['title', 'head']),
  tool('github_merge_pull', 'Fusionne une pull request.', {
    number: N('Numéro de la pull request.'),
    method: S('merge, squash ou rebase (défaut squash).'),
  }, ['number']),
  tool('github_write_files', 'Crée ou modifie un ou plusieurs fichiers et pousse un commit. C’est l’outil à utiliser pour écrire du code.', {
    message: S('Message de commit.'),
    branch: S('Branche à modifier (défaut : branche par défaut). Pour proposer une PR, crée d’abord une branche avec github_create_branch.'),
    files: {
      type: 'array',
      description: 'Fichiers à écrire : contenu complet, pas un diff.',
      items: {
        type: 'object',
        properties: {
          path: S('Chemin du fichier.'),
          content: S('Contenu complet du fichier.'),
        },
        required: ['path', 'content'],
        additionalProperties: false,
      },
    },
  }, ['message', 'files']),
  tool('github_delete_file', 'Supprime un fichier et pousse un commit.', {
    path: S('Chemin du fichier.'),
    message: S('Message de commit.'),
    branch: S('Branche.'),
  }, ['path', 'message']),
  tool('github_create_branch', 'Crée une branche à partir d’une autre.', {
    name: S('Nom de la nouvelle branche.'),
    from: S('Branche source (défaut : branche par défaut).'),
  }, ['name']),
  tool('github_list_workflow_runs', 'Liste les exécutions GitHub Actions du dépôt.', {
    limit: N('Nombre maximum (défaut 10).'),
  }),
  tool('github_run_workflow', 'Déclenche un workflow GitHub Actions.', {
    workflow: S('Nom du fichier de workflow, par exemple build-apk.yml.'),
    ref: S('Branche (défaut : branche par défaut).'),
  }, ['workflow']),
];

const SITE_TOOLS = [
  siteTool(
    'site_create',
    'Publie un site web de test et renvoie son adresse publique. Fournis une page HTML complète et autonome : styles et scripts inclus dans le fichier.',
    {
      title: S('Titre lisible du site.'),
      html: S('Contenu complet du fichier HTML : doctype, head, body et styles inclus.'),
    },
    ['html'],
  ),
  siteTool(
    'site_update',
    'Remplace le contenu d’un site déjà publié. L’adresse publique ne change pas.',
    {
      slug: S('Identifiant du site, renvoyé par site_create ou site_list.'),
      title: S('Nouveau titre (facultatif).'),
      html: S('Nouveau contenu HTML complet de la page.'),
    },
    ['slug', 'html'],
  ),
  siteTool('site_list', 'Liste les sites publiés par cette personne avec leur adresse.', {}),
  siteTool(
    'site_delete',
    'Supprime définitivement un site publié : son adresse cesse de fonctionner.',
    { slug: S('Identifiant du site à supprimer.') },
    ['slug'],
  ),
];

function githubConfigured(ctx) {
  return Boolean(ctx && typeof ctx.GITHUB_TOKEN === 'string' && ctx.GITHUB_TOKEN.trim().length > 0);
}

/** L'application OAuth est-elle installée sur ce relais ? */
function githubOauthConfigured(env) {
  return (
    typeof env.GITHUB_CLIENT_ID === 'string' &&
    env.GITHUB_CLIENT_ID.trim().length > 0 &&
    typeof env.GITHUB_CLIENT_SECRET === 'string' &&
    env.GITHUB_CLIENT_SECRET.trim().length > 0
  );
}

function envDefaultRepo(env) {
  const raw = typeof env.GITHUB_REPO === 'string' ? env.GITHUB_REPO.trim() : '';
  const repo = raw || DEFAULT_GITHUB_REPO;
  return /^[\w.-]+\/[\w.-]+$/.test(repo) ? repo : DEFAULT_GITHUB_REPO;
}

/** Dépôt visé : argument de l'outil, puis dépôt courant du compte. Vide =
 * compte personnel sans dépôt choisi, l'outil demande alors de préciser. */
function ghRepo(ctx, override) {
  const explicit = typeof override === 'string' ? override.trim() : '';
  let repo = explicit || (typeof ctx.GITHUB_REPO === 'string' ? ctx.GITHUB_REPO.trim() : '');
  if (repo && !repo.includes('/') && ctx.GITHUB_LOGIN) repo = `${ctx.GITHUB_LOGIN}/${repo}`;
  if (!repo) return ctx.GITHUB_LOGIN ? '' : DEFAULT_GITHUB_REPO;
  return /^[\w.-]+\/[\w.-]+$/.test(repo) ? repo : '';
}

async function gh(env, path, init = {}) {
  const res = await fetch(`${GITHUB_API}${path}`, {
    method: init.method || 'GET',
    headers: {
      authorization: `Bearer ${env.GITHUB_TOKEN.trim()}`,
      accept: 'application/vnd.github+json',
      'x-github-api-version': '2022-11-28',
      'user-agent': 'WORLD-AI-relay',
      ...(init.body ? { 'content-type': 'application/json' } : {}),
    },
    body: init.body ? JSON.stringify(init.body) : undefined,
  });
  const raw = await res.text();
  let data = null;
  try {
    data = raw ? JSON.parse(raw) : null;
  } catch (_) {
    data = null;
  }
  return { ok: res.ok, status: res.status, data };
}

function ghError(result) {
  const message =
    result?.data && typeof result.data.message === 'string'
      ? result.data.message
      : `GitHub a répondu ${result?.status ?? '?'}`;
  return { ok: false, error: message, status: result?.status ?? 0 };
}

function safePath(value) {
  if (typeof value !== 'string') return null;
  const path = value.trim().replace(/^\/+/, '');
  if (path.length === 0 || path.length > 400) return null;
  if (path.includes('..')) return null;
  return path;
}

function clip(text, max = MAX_TOOL_RESULT_CHARS) {
  if (typeof text !== 'string') return '';
  return text.length > max ? `${text.slice(0, max)}\n… (tronqué)` : text;
}

async function defaultBranch(env, repo) {
  const info = await gh(env, `/repos/${repo}`);
  if (info.ok && typeof info.data?.default_branch === 'string') {
    return info.data.default_branch;
  }
  return 'main';
}

/** Exécute un appel d’outil GitHub et renvoie { result, summary, ok }. */
async function runGithubTool(ctx, name, args) {
  const env = ctx;
  const a = args && typeof args === 'object' ? args : {};

  if (name === 'github_list_repos') {
    const limit = Math.min(Math.max(Number(a.limit) || 30, 1), 100);
    const r = await gh(
      env,
      '/user/repos?sort=updated&per_page=100&affiliation=owner,collaborator,organization_member',
    );
    if (!r.ok) return { ok: false, summary: 'Dépôts illisibles', result: ghError(r) };
    const repos = (Array.isArray(r.data) ? r.data : []).slice(0, limit).map((item) => ({
      full_name: item.full_name,
      private: Boolean(item.private),
      default_branch: item.default_branch,
      can_push: Boolean(item.permissions?.push),
      updated_at: item.updated_at,
    }));
    return { ok: true, summary: `${repos.length} dépôt(s)`, result: { repos } };
  }

  const repo = ghRepo(env, a.repo);
  if (!repo) {
    return {
      ok: false,
      summary: 'Dépôt à préciser',
      result: {
        error:
          'Aucun dépôt courant : appelle github_list_repos, puis indique « repo » (« propriétaire/nom »).',
      },
    };
  }
  const base = `/repos/${repo}`;

  switch (name) {
    case 'github_repo_info': {
      const r = await gh(env, base);
      if (!r.ok) return { ok: false, summary: 'Dépôt illisible', result: ghError(r) };
      return {
        ok: true,
        summary: `Infos de ${repo}`,
        result: {
          full_name: r.data.full_name,
          description: r.data.description,
          default_branch: r.data.default_branch,
          language: r.data.language,
          private: r.data.private,
          open_issues: r.data.open_issues_count,
          stars: r.data.stargazers_count,
          updated_at: r.data.updated_at,
        },
      };
    }

    case 'github_list_files': {
      const branch = typeof a.branch === 'string' && a.branch ? a.branch : await defaultBranch(env, repo);
      const r = await gh(env, `${base}/git/trees/${encodeURIComponent(branch)}?recursive=1`);
      if (!r.ok) return { ok: false, summary: 'Arborescence illisible', result: ghError(r) };
      const prefix = typeof a.path === 'string' ? a.path.trim().replace(/^\/+/, '') : '';
      const limit = Math.min(Math.max(Number(a.limit) || 200, 1), 500);
      const paths = (Array.isArray(r.data?.tree) ? r.data.tree : [])
        .filter((item) => item.type === 'blob')
        .map((item) => item.path)
        .filter((p) => (prefix ? p.startsWith(prefix) : true))
        .slice(0, limit);
      return { ok: true, summary: `${paths.length} fichier(s) listé(s)`, result: { branch, files: paths } };
    }

    case 'github_read_file': {
      const path = safePath(a.path);
      if (!path) return { ok: false, summary: 'Chemin invalide', result: { error: 'Chemin invalide.' } };
      const branch = typeof a.branch === 'string' && a.branch ? `?ref=${encodeURIComponent(a.branch)}` : '';
      const r = await gh(env, `${base}/contents/${path.split('/').map(encodeURIComponent).join('/')}${branch}`);
      if (!r.ok) return { ok: false, summary: `Lecture impossible : ${path}`, result: ghError(r) };
      if (Array.isArray(r.data)) {
        return { ok: true, summary: `Dossier ${path}`, result: { path, entries: r.data.map((e) => ({ name: e.name, type: e.type })) } };
      }
      let content = '';
      if (r.data?.encoding === 'base64' && typeof r.data.content === 'string') {
        try {
          content = atob(r.data.content.replace(/\n/g, ''));
        } catch (_) {
          content = '';
        }
      }
      return {
        ok: true,
        summary: `Lecture de ${path}`,
        result: { path, size: r.data?.size, sha: r.data?.sha, content: clip(content) },
      };
    }

    case 'github_search_code': {
      const query = typeof a.query === 'string' ? a.query.trim() : '';
      if (!query) return { ok: false, summary: 'Recherche vide', result: { error: 'Requête vide.' } };
      const r = await gh(
        env,
        `/search/code?q=${encodeURIComponent(`${query} repo:${repo}`)}&per_page=${Math.min(Math.max(Number(a.limit) || 20, 1), 50)}`,
      );
      if (!r.ok) return { ok: false, summary: 'Recherche impossible', result: ghError(r) };
      const items = (Array.isArray(r.data?.items) ? r.data.items : []).map((item) => ({
        path: item.path,
        matches: (item.text_matches || []).map((m) => clip(m.fragment, 400)).join('\n---\n'),
      }));
      return { ok: true, summary: `${items.length} résultat(s) pour « ${query} »`, result: { query, items } };
    }

    case 'github_list_branches': {
      const r = await gh(env, `${base}/branches?per_page=100`);
      if (!r.ok) return { ok: false, summary: 'Branches illisibles', result: ghError(r) };
      return { ok: true, summary: 'Branches listées', result: { branches: r.data.map((b) => b.name) } };
    }

    case 'github_list_commits': {
      const limit = Math.min(Math.max(Number(a.limit) || 15, 1), 50);
      const params = new URLSearchParams({ per_page: String(limit) });
      if (typeof a.branch === 'string' && a.branch) params.set('sha', a.branch);
      if (typeof a.path === 'string' && a.path) params.set('path', a.path);
      const r = await gh(env, `${base}/commits?${params.toString()}`);
      if (!r.ok) return { ok: false, summary: 'Commits illisibles', result: ghError(r) };
      const commits = r.data.map((c) => ({
        sha: c.sha?.slice(0, 7),
        message: clip(c.commit?.message || '', 300),
        author: c.commit?.author?.name,
        date: c.commit?.author?.date,
      }));
      return { ok: true, summary: `${commits.length} commit(s)`, result: { commits } };
    }

    case 'github_list_issues': {
      const state = ['open', 'closed', 'all'].includes(a.state) ? a.state : 'open';
      const limit = Math.min(Math.max(Number(a.limit) || 20, 1), 50);
      const r = await gh(env, `${base}/issues?state=${state}&per_page=${limit}`);
      if (!r.ok) return { ok: false, summary: 'Issues illisibles', result: ghError(r) };
      const items = r.data.map((i) => ({
        number: i.number,
        title: i.title,
        state: i.state,
        is_pull_request: Boolean(i.pull_request),
        user: i.user?.login,
      }));
      return { ok: true, summary: `${items.length} issue(s)`, result: { issues: items } };
    }

    case 'github_get_issue': {
      const number = Number(a.number);
      if (!Number.isFinite(number)) return { ok: false, summary: 'Numéro manquant', result: { error: 'Numéro invalide.' } };
      const [issue, comments] = await Promise.all([
        gh(env, `${base}/issues/${number}`),
        gh(env, `${base}/issues/${number}/comments?per_page=50`),
      ]);
      if (!issue.ok) return { ok: false, summary: `Issue #${number} illisible`, result: ghError(issue) };
      return {
        ok: true,
        summary: `Issue #${number} lue`,
        result: {
          number: issue.data.number,
          title: issue.data.title,
          state: issue.data.state,
          body: clip(issue.data.body || '', 4000),
          comments: (Array.isArray(comments.data) ? comments.data : []).map((c) => ({
            user: c.user?.login,
            body: clip(c.body || '', 1200),
          })),
        },
      };
    }

    case 'github_create_issue': {
      const title = typeof a.title === 'string' ? a.title.trim() : '';
      if (!title) return { ok: false, summary: 'Titre manquant', result: { error: 'Titre requis.' } };
      const r = await gh(env, `${base}/issues`, {
        method: 'POST',
        body: {
          title,
          body: typeof a.body === 'string' ? a.body : '',
          labels: Array.isArray(a.labels) ? a.labels.filter((l) => typeof l === 'string') : undefined,
        },
      });
      if (!r.ok) return { ok: false, summary: 'Création refusée', result: ghError(r) };
      return { ok: true, summary: `Issue #${r.data.number} créée`, result: { number: r.data.number, url: r.data.html_url } };
    }

    case 'github_comment_issue': {
      const number = Number(a.number);
      const body = typeof a.body === 'string' ? a.body : '';
      if (!Number.isFinite(number) || !body.trim()) {
        return { ok: false, summary: 'Commentaire incomplet', result: { error: 'Numéro et texte requis.' } };
      }
      const r = await gh(env, `${base}/issues/${number}/comments`, { method: 'POST', body: { body } });
      if (!r.ok) return { ok: false, summary: 'Commentaire refusé', result: ghError(r) };
      return { ok: true, summary: `Commentaire sur #${number}`, result: { url: r.data.html_url } };
    }

    case 'github_set_issue_state': {
      const number = Number(a.number);
      const state = a.state === 'open' ? 'open' : 'closed';
      if (!Number.isFinite(number)) return { ok: false, summary: 'Numéro manquant', result: { error: 'Numéro invalide.' } };
      const r = await gh(env, `${base}/issues/${number}`, { method: 'PATCH', body: { state } });
      if (!r.ok) return { ok: false, summary: 'Changement refusé', result: ghError(r) };
      return { ok: true, summary: `Issue #${number} → ${state}`, result: { state: r.data.state } };
    }

    case 'github_list_pulls': {
      const state = ['open', 'closed', 'all'].includes(a.state) ? a.state : 'open';
      const limit = Math.min(Math.max(Number(a.limit) || 20, 1), 50);
      const r = await gh(env, `${base}/pulls?state=${state}&per_page=${limit}`);
      if (!r.ok) return { ok: false, summary: 'PR illisibles', result: ghError(r) };
      const pulls = r.data.map((p) => ({
        number: p.number,
        title: p.title,
        state: p.state,
        head: p.head?.ref,
        base: p.base?.ref,
        user: p.user?.login,
      }));
      return { ok: true, summary: `${pulls.length} PR`, result: { pulls } };
    }

    case 'github_get_pull': {
      const number = Number(a.number);
      if (!Number.isFinite(number)) return { ok: false, summary: 'Numéro manquant', result: { error: 'Numéro invalide.' } };
      const [pull, files] = await Promise.all([
        gh(env, `${base}/pulls/${number}`),
        gh(env, `${base}/pulls/${number}/files?per_page=50`),
      ]);
      if (!pull.ok) return { ok: false, summary: `PR #${number} illisible`, result: ghError(pull) };
      return {
        ok: true,
        summary: `PR #${number} lue`,
        result: {
          number: pull.data.number,
          title: pull.data.title,
          state: pull.data.state,
          merged: pull.data.merged,
          head: pull.data.head?.ref,
          base: pull.data.base?.ref,
          body: clip(pull.data.body || '', 3000),
          files: (Array.isArray(files.data) ? files.data : []).map((f) => ({
            path: f.filename,
            status: f.status,
            additions: f.additions,
            deletions: f.deletions,
          })),
        },
      };
    }

    case 'github_create_pull': {
      const title = typeof a.title === 'string' ? a.title.trim() : '';
      const head = typeof a.head === 'string' ? a.head.trim() : '';
      if (!title || !head) return { ok: false, summary: 'PR incomplète', result: { error: 'Titre et branche source requis.' } };
      const baseBranch = typeof a.base === 'string' && a.base ? a.base : await defaultBranch(env, repo);
      const r = await gh(env, `${base}/pulls`, {
        method: 'POST',
        body: {
          title,
          head,
          base: baseBranch,
          body: typeof a.body === 'string' ? a.body : '',
          draft: a.draft === true,
        },
      });
      if (!r.ok) return { ok: false, summary: 'PR refusée', result: ghError(r) };
      return {
        ok: true,
        summary: `PR #${r.data.number} ouverte (${head} → ${baseBranch})`,
        result: { number: r.data.number, url: r.data.html_url },
      };
    }

    case 'github_merge_pull': {
      const number = Number(a.number);
      if (!Number.isFinite(number)) return { ok: false, summary: 'Numéro manquant', result: { error: 'Numéro invalide.' } };
      const method = ['merge', 'squash', 'rebase'].includes(a.method) ? a.method : 'squash';
      const r = await gh(env, `${base}/pulls/${number}/merge`, { method: 'PUT', body: { merge_method: method } });
      if (!r.ok) return { ok: false, summary: 'Fusion refusée', result: ghError(r) };
      return { ok: true, summary: `PR #${number} fusionnée`, result: { merged: r.data.merged, sha: r.data.sha } };
    }

    case 'github_create_branch': {
      const name = typeof a.name === 'string' ? a.name.trim() : '';
      if (!/^[\w./-]{1,200}$/.test(name)) {
        return { ok: false, summary: 'Nom invalide', result: { error: 'Nom de branche invalide.' } };
      }
      const from = typeof a.from === 'string' && a.from ? a.from : await defaultBranch(env, repo);
      const ref = await gh(env, `${base}/git/ref/heads/${encodeURIComponent(from)}`);
      if (!ref.ok) return { ok: false, summary: 'Branche source inconnue', result: ghError(ref) };
      const r = await gh(env, `${base}/git/refs`, {
        method: 'POST',
        body: { ref: `refs/heads/${name}`, sha: ref.data.object.sha },
      });
      if (!r.ok) return { ok: false, summary: 'Création de branche refusée', result: ghError(r) };
      return { ok: true, summary: `Branche ${name} créée depuis ${from}`, result: { branch: name } };
    }

    case 'github_write_files': {
      const files = Array.isArray(a.files) ? a.files : [];
      const message = typeof a.message === 'string' && a.message.trim() ? a.message.trim() : 'Mise à jour depuis WORLD-AI';
      if (files.length === 0) return { ok: false, summary: 'Aucun fichier', result: { error: 'Aucun fichier fourni.' } };
      if (files.length > MAX_WRITE_FILES) {
        return { ok: false, summary: 'Trop de fichiers', result: { error: `Maximum ${MAX_WRITE_FILES} fichiers par commit.` } };
      }
      const branch = typeof a.branch === 'string' && a.branch ? a.branch : await defaultBranch(env, repo);
      const entries = [];
      for (const file of files) {
        const path = safePath(file?.path);
        const content = typeof file?.content === 'string' ? file.content : '';
        if (!path) return { ok: false, summary: 'Chemin invalide', result: { error: 'Chemin de fichier invalide.' } };
        if (content.length > MAX_FILE_CONTENT_CHARS) {
          return { ok: false, summary: 'Fichier trop gros', result: { error: `${path} dépasse la taille maximale.` } };
        }
        entries.push({ path, content });
      }

      const ref = await gh(env, `${base}/git/ref/heads/${encodeURIComponent(branch)}`);
      if (!ref.ok) return { ok: false, summary: `Branche ${branch} introuvable`, result: ghError(ref) };
      const parentSha = ref.data.object.sha;
      const parent = await gh(env, `${base}/git/commits/${parentSha}`);
      if (!parent.ok) return { ok: false, summary: 'Commit parent illisible', result: ghError(parent) };

      const blobs = [];
      for (const entry of entries) {
        const blob = await gh(env, `${base}/git/blobs`, {
          method: 'POST',
          body: { content: entry.content, encoding: 'utf-8' },
        });
        if (!blob.ok) return { ok: false, summary: `Écriture refusée : ${entry.path}`, result: ghError(blob) };
        blobs.push({ path: entry.path, mode: '100644', type: 'blob', sha: blob.data.sha });
      }

      const tree = await gh(env, `${base}/git/trees`, {
        method: 'POST',
        body: { base_tree: parent.data.tree.sha, tree: blobs },
      });
      if (!tree.ok) return { ok: false, summary: 'Arbre refusé', result: ghError(tree) };

      const commit = await gh(env, `${base}/git/commits`, {
        method: 'POST',
        body: { message, tree: tree.data.sha, parents: [parentSha] },
      });
      if (!commit.ok) return { ok: false, summary: 'Commit refusé', result: ghError(commit) };

      const update = await gh(env, `${base}/git/refs/heads/${encodeURIComponent(branch)}`, {
        method: 'PATCH',
        body: { sha: commit.data.sha, force: false },
      });
      if (!update.ok) return { ok: false, summary: 'Branche non mise à jour', result: ghError(update) };

      return {
        ok: true,
        summary: `Commit ${commit.data.sha.slice(0, 7)} sur ${branch} (${entries.length} fichier(s))`,
        result: {
          sha: commit.data.sha,
          branch,
          files: entries.map((e) => e.path),
          url: commit.data.html_url,
        },
      };
    }

    case 'github_delete_file': {
      const path = safePath(a.path);
      const message = typeof a.message === 'string' && a.message.trim() ? a.message.trim() : 'Suppression depuis WORLD-AI';
      if (!path) return { ok: false, summary: 'Chemin invalide', result: { error: 'Chemin invalide.' } };
      const branch = typeof a.branch === 'string' && a.branch ? a.branch : await defaultBranch(env, repo);
      const current = await gh(env, `${base}/contents/${path}?ref=${encodeURIComponent(branch)}`);
      if (!current.ok || !current.data?.sha) {
        return { ok: false, summary: `Fichier introuvable : ${path}`, result: ghError(current) };
      }
      const r = await gh(env, `${base}/contents/${path}`, {
        method: 'DELETE',
        body: { message, sha: current.data.sha, branch },
      });
      if (!r.ok) return { ok: false, summary: 'Suppression refusée', result: ghError(r) };
      return { ok: true, summary: `Fichier supprimé : ${path}`, result: { path, branch } };
    }

    case 'github_list_workflow_runs': {
      const limit = Math.min(Math.max(Number(a.limit) || 10, 1), 30);
      const r = await gh(env, `${base}/actions/runs?per_page=${limit}`);
      if (!r.ok) return { ok: false, summary: 'Actions illisibles', result: ghError(r) };
      const runs = (Array.isArray(r.data?.workflow_runs) ? r.data.workflow_runs : []).map((run) => ({
        name: run.name,
        branch: run.head_branch,
        status: run.status,
        conclusion: run.conclusion,
        created_at: run.created_at,
        url: run.html_url,
      }));
      return { ok: true, summary: `${runs.length} exécution(s)`, result: { runs } };
    }

    case 'github_run_workflow': {
      const workflow = typeof a.workflow === 'string' ? a.workflow.trim() : '';
      if (!workflow) return { ok: false, summary: 'Workflow manquant', result: { error: 'Nom du workflow requis.' } };
      const ref = typeof a.ref === 'string' && a.ref ? a.ref : await defaultBranch(env, repo);
      const r = await gh(env, `${base}/actions/workflows/${encodeURIComponent(workflow)}/dispatches`, {
        method: 'POST',
        body: { ref },
      });
      if (!r.ok) return { ok: false, summary: 'Déclenchement refusé', result: ghError(r) };
      return { ok: true, summary: `Workflow ${workflow} déclenché sur ${ref}`, result: { workflow, ref } };
    }

    default:
      return { ok: false, summary: 'Outil inconnu', result: { error: `Outil inconnu : ${name}` } };
  }
}

async function groqCall(env, body) {
  try {
    const res = await fetch(GROQ_URL, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${env.GROQ_API_KEY}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    const data = await res.json().catch(() => null);
    return { ok: res.ok, status: res.status, data, networkError: false };
  } catch (error) {
    console.error('Groq injoignable', error);
    return { ok: false, status: 0, data: null, networkError: true };
  }
}

function groqFailure(result) {
  if (result.networkError) {
    return fail(502, 'upstream', 'L’IA est momentanément injoignable.');
  }
  if (result.status === 401 || result.status === 403) {
    console.error('Clé Groq refusée', result.status);
    return fail(503, 'not_configured', 'La clé de l’IA est invalide.');
  }
  if (result.status === 429) {
    return fail(429, 'upstream_limit', 'L’IA est très sollicitée, réessaie dans un instant.');
  }
  console.error('Groq a répondu', result.status);
  return fail(502, 'upstream', 'L’IA n’a pas pu répondre.');
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

  // GitHub de la personne connectée : son jeton, son compte, ses dépôts. Un
  // invité ne peut utiliser que le jeton du relais s'il en existe un.
  const ghCtx = await githubContext(request, env);
  const ghReady = githubConfigured(ghCtx);
  // Les sites appartiennent à un compte WORLD-AI : un invité peut discuter,
  // mais il n’a rien à publier ni à retrouver.
  const viewer = await currentUser(request, env.DB);
  const sitesReady = Boolean(viewer);
  const tools = [...(ghReady ? GITHUB_TOOLS : []), ...(sitesReady ? SITE_TOOLS : [])];

  const sitePrompt = sitesReady
    ? ' Tu peux aussi créer un site web de test : écris une page HTML complète et autonome ' +
      '(styles et scripts dans le fichier), appelle site_create, puis donne l’adresse publique obtenue. ' +
      'site_update remplace le contenu d’un site existant, site_list retrouve les sites publiés ' +
      'et site_delete les supprime. Ces adresses sont publiques : n’y mets aucune donnée sensible.'
    : '';

  const systemPrompt = ghReady
    ? `${SYSTEM_PROMPT} Tu es connecté au compte GitHub ${ghCtx.GITHUB_LOGIN || 'demandé'} et tu peux agir sur ses dépôts grâce aux outils fournis` +
      (ghCtx.GITHUB_REPO
        ? ` (dépôt courant : ${ghCtx.GITHUB_REPO}). `
        : ' (aucun dépôt courant : appelle github_list_repos, puis indique « repo »). ') +
      'Lis le code avant de le modifier, écris des fichiers complets, et crée une branche puis une pull request ' +
      'plutôt que de pousser directement sur la branche par défaut quand le changement est important. ' +
      'Annonce brièvement ce que tu fais, fais-le, puis résume le résultat. ' +
      'N’invente jamais une action : si un outil échoue, dis-le avec l’erreur réelle.' +
      sitePrompt
    : `${SYSTEM_PROMPT} Tu n’as aucun accès à GitHub : ne prétends jamais avoir lu ou modifié un dépôt. Tu peux proposer de connecter un compte GitHub depuis les paramètres de l’application.` +
      sitePrompt;

  const callTool = async (name, args) => {
    if (name.startsWith('site_')) {
      if (!sitesReady) {
        return {
          ok: false,
          summary: 'Compte requis',
          result: {
            error:
              'Publier un site demande un compte WORLD-AI : connecte-toi depuis les paramètres de l’application.',
          },
        };
      }
      return runSiteTool(
        { env, userId: viewer.id, origin: new URL(request.url).origin },
        name,
        args,
      );
    }
    if (!ghReady) {
      return {
        ok: false,
        summary: 'GitHub non connecté',
        result: {
          error:
            'Aucun compte GitHub connecté : ouvre Paramètres → GitHub dans l’application pour lier ton compte.',
        },
      };
    }
    return runGithubTool(ghCtx, name, args);
  };

  const groqMessages = [{ role: 'system', content: systemPrompt }];
  for (let i = 0; i < messages.length; i += 1) {
    const msg = messages[i];
    const isLast = i === messages.length - 1;
    const attachments = isLast && msg.role === 'user' && Array.isArray(msg.attachments) ? msg.attachments : [];
    if (msg.role === 'user' && attachments.length > 0) {
      const parts = [];
      let text = msg.content;
      for (const att of attachments) {
        if (!att || typeof att !== 'object') continue;
        const mime = typeof att.mime === 'string' ? att.mime : '';
        const name = typeof att.name === 'string' ? att.name : 'fichier';
        const data = typeof att.data === 'string' ? att.data : '';
        if (!data) continue;
        if (data.length > MAX_ATTACHMENT_BYTES * 4 / 3 + 1024) continue;
        if (isImageMime(mime)) {
          parts.push({ type: 'image_url', image_url: { url: data } });
          continue;
        }
        if (isTextLikeMime(mime) || mime === 'application/pdf') {
          try {
            let decoded = '';
            const b64 = data.includes(',') ? data.split(',')[1] : data;
            decoded = atob(b64);
            if (decoded.length > 0 && decoded.length <= MAX_ATTACHMENT_CHARS) {
              text += `\n\n[Pièce jointe : ${name}]\n${decoded}`;
            } else if (decoded.length > MAX_ATTACHMENT_CHARS) {
              text += `\n\n[Pièce jointe : ${name}]\n${decoded.slice(0, MAX_ATTACHMENT_CHARS)}\n... (tronqué)`;
            }
          } catch (_) {
            text += `\n\n[Pièce jointe : ${name}] (contenu non lisible)`;
          }
          continue;
        }
        text += `\n\n[Pièce jointe : ${name} (${mime || 'inconnu'})]`;
      }
      if (parts.length > 0) {
        const contentParts = [];
        if (text.trim()) contentParts.push({ type: 'text', text: text.trim() });
        contentParts.push(...parts);
        groqMessages.push({ role: 'user', content: contentParts });
      } else {
        groqMessages.push({ role: 'user', content: text.trim() });
      }
    } else {
      groqMessages.push({ role: msg.role, content: msg.content });
    }
  }

  let toolMode = tools.length > 0;
  const actions = [];
  let text = '';

  for (let step = 0; step < MAX_TOOL_STEPS; step += 1) {
    const result = await groqCall(env, {
      model,
      messages: groqMessages,
      max_completion_tokens: MAX_COMPLETION_TOKENS,
      temperature: 0.7,
      ...(toolMode ? { tools, tool_choice: 'auto' } : {}),
    });
    if (!result.ok) {
      // Certains modèles ne savent pas appeler d’outil : on repasse en
      // discussion simple plutôt que de renvoyer une erreur au client.
      if (toolMode && result.status === 400) {
        toolMode = false;
        continue;
      }
      return groqFailure(result);
    }

    const choice = result.data?.choices?.[0]?.message;
    const calls = Array.isArray(choice?.tool_calls) ? choice.tool_calls : [];
    if (calls.length === 0) {
      text = typeof choice?.content === 'string' ? choice.content.trim() : '';
      break;
    }

    groqMessages.push({
      role: 'assistant',
      content: typeof choice?.content === 'string' ? choice.content : '',
      tool_calls: calls,
    });

    for (const call of calls) {
      const name = call?.function?.name || '';
      let args = {};
      try {
        args = JSON.parse(call?.function?.arguments || '{}');
      } catch (_) {
        args = {};
      }
      let outcome;
      try {
        outcome = await callTool(name, args);
      } catch (error) {
        outcome = {
          ok: false,
          summary: `${name} a échoué`,
          result: { error: String(error?.message || error) },
        };
      }
      actions.push({ tool: name, summary: outcome.summary, ok: outcome.ok });
      groqMessages.push({
        role: 'tool',
        tool_call_id: call.id,
        content: clip(JSON.stringify(outcome.result ?? {}), 8000),
      });
    }

    if (step === MAX_TOOL_STEPS - 1) {
      groqMessages.push({
        role: 'system',
        content: 'Tu as atteint le nombre maximal d’actions pour ce message. Résume ce qui a été fait et ce qui reste à faire, sans appeler d’autre outil.',
      });
    }
  }

  if (!text) {
    // Filet de sécurité : une dernière passe sans outils pour obtenir un texte.
    const last = await groqCall(env, {
      model,
      messages: groqMessages,
      max_completion_tokens: MAX_COMPLETION_TOKENS,
      temperature: 0.7,
    });
    if (!last.ok) return groqFailure(last);
    text = typeof last.data?.choices?.[0]?.message?.content === 'string'
      ? last.data.choices[0].message.content.trim()
      : '';
  }

  if (!text) {
    return fail(502, 'empty', 'Réponse vide de l’IA, réessaie.');
  }

  await Promise.all([bump(env.DB, day, device), bump(env.DB, day, 'global')]);

  const remaining =
    DEVICE_DAILY_LIMIT > 0
      ? Math.max(0, DEVICE_DAILY_LIMIT - (used + 1))
      : null;
  return json({ reply: text, model, remaining, actions });
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

/* ------------------------------------------- Comptes GitHub (OAuth device) */

/** Jeton GitHub de la personne connectée, ou celui du relais pour un invité. */
async function githubContext(request, env) {
  const user = env.DB ? await currentUser(request, env.DB) : null;
  const account = user ? await githubAccount(env, user.id) : null;
  const fallback =
    typeof env.GITHUB_TOKEN === 'string' ? env.GITHUB_TOKEN.trim() : '';
  const token = account?.token || (user ? '' : fallback);
  if (!token) return null;
  return {
    GITHUB_TOKEN: token,
    GITHUB_LOGIN: account?.login || '',
    GITHUB_REPO: (account?.default_repo || '').trim() || (user ? '' : envDefaultRepo(env)),
  };
}

async function githubAccount(env, userId) {
  if (!env.DB) return null;
  const row = await env.DB.prepare(
    'SELECT login, token, scopes, default_repo FROM github_accounts WHERE user_id = ?',
  )
    .bind(userId)
    .first();
  return row ?? null;
}

async function saveGithubAccount(env, userId, login, token, scopes) {
  const now = Date.now();
  await env.DB.prepare(
    'INSERT INTO github_accounts (user_id, login, token, scopes, default_repo, created_at, updated_at) ' +
      'VALUES (?, ?, ?, ?, "", ?, ?) ' +
      'ON CONFLICT(user_id) DO UPDATE SET login = excluded.login, token = excluded.token, ' +
      'scopes = excluded.scopes, updated_at = excluded.updated_at',
  )
    .bind(userId, login, token, scopes, now, now)
    .run();
}

/** Lit le compte GitHub derrière un jeton : sert à valider avant de le garder. */
async function githubViewer(token) {
  try {
    const res = await fetch(`${GITHUB_API}/user`, {
      headers: {
        authorization: `Bearer ${token}`,
        accept: 'application/vnd.github+json',
        'x-github-api-version': '2022-11-28',
        'user-agent': 'WORLD-AI-relay',
      },
    });
    if (!res.ok) return { ok: false, status: res.status };
    const data = await res.json().catch(() => null);
    if (!data || typeof data.login !== 'string') return { ok: false, status: 0 };
    return { ok: true, login: data.login };
  } catch (error) {
    console.error('GitHub /user injoignable', error);
    return { ok: false, status: 0 };
  }
}

async function signedIn(request, env) {
  if (!env.DB) return null;
  await ensureSchema(env.DB);
  return currentUser(request, env.DB);
}

/** État de la connexion GitHub du compte. */
async function githubStatusRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) {
    return json({
      ok: true,
      signedIn: false,
      deviceFlow: githubOauthConfigured(env),
      connected: false,
      login: null,
      defaultRepo: '',
    });
  }
  const account = await githubAccount(env, user.id);
  return json({
    ok: true,
    signedIn: true,
    deviceFlow: githubOauthConfigured(env),
    connected: Boolean(account),
    login: account?.login ?? null,
    defaultRepo: account?.default_repo || '',
  });
}

/** Démarre une connexion OAuth : le relais obtient un code à recopier. */
async function githubDeviceStartRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) {
    return fail(401, 'unauthorized', 'Connecte-toi à un compte WORLD-AI pour lier ton GitHub.');
  }
  if (!githubOauthConfigured(env)) {
    return fail(
      503,
      'not_configured',
      'La connexion GitHub n’est pas installée sur le relais : ajoute GITHUB_CLIENT_ID et GITHUB_CLIENT_SECRET.',
    );
  }
  let data = null;
  let status = 0;
  try {
    const res = await fetch(GITHUB_DEVICE_CODE_URL, {
      method: 'POST',
      headers: { accept: 'application/json', 'content-type': 'application/json' },
      body: JSON.stringify({ client_id: env.GITHUB_CLIENT_ID.trim(), scope: GITHUB_SCOPES }),
    });
    status = res.status;
    data = await res.json().catch(() => null);
  } catch (error) {
    console.error('GitHub device/code injoignable', error);
  }
  if (!data || typeof data.device_code !== 'string' || typeof data.user_code !== 'string') {
    console.error('GitHub device/code a répondu', status);
    return fail(502, 'upstream', 'GitHub n’a pas voulu démarrer la connexion.');
  }
  const id = uid();
  const interval = Math.min(Math.max(Number(data.interval) || 5, 3), 30);
  const expiresIn = Math.min(Math.max(Number(data.expires_in) || 900, 60), 1800);
  await env.DB.prepare('DELETE FROM github_pending WHERE user_id = ?').bind(user.id).run();
  await env.DB.prepare(
    'INSERT INTO github_pending (id, user_id, device_code, interval, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)',
  )
    .bind(id, user.id, data.device_code, interval, Date.now() + expiresIn * 1000, Date.now())
    .run();
  return json({
    ok: true,
    id,
    userCode: data.user_code,
    verificationUri:
      typeof data.verification_uri === 'string'
        ? data.verification_uri
        : 'https://github.com/login/device',
    interval,
    expiresIn,
  });
}

/** Suite du device flow : l'application interroge le relais, qui interroge
 * GitHub, jusqu'à ce que la personne ait validé le code. */
async function githubDevicePollRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const payload = await request.json().catch(() => null);
  const id = typeof payload?.id === 'string' ? payload.id : '';
  if (!id) return fail(400, 'bad_request', 'Identifiant de connexion manquant.');

  const pending = await env.DB.prepare(
    'SELECT device_code, expires_at FROM github_pending WHERE id = ? AND user_id = ?',
  )
    .bind(id, user.id)
    .first();
  if (!pending) return json({ ok: true, status: 'expired' });
  if (pending.expires_at <= Date.now()) {
    await env.DB.prepare('DELETE FROM github_pending WHERE id = ?').bind(id).run();
    return json({ ok: true, status: 'expired' });
  }

  let data = null;
  try {
    const res = await fetch(GITHUB_ACCESS_TOKEN_URL, {
      method: 'POST',
      headers: { accept: 'application/json', 'content-type': 'application/json' },
      body: JSON.stringify({
        client_id: env.GITHUB_CLIENT_ID.trim(),
        client_secret: env.GITHUB_CLIENT_SECRET.trim(),
        device_code: pending.device_code,
        grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
      }),
    });
    data = await res.json().catch(() => null);
  } catch (error) {
    console.error('GitHub access_token injoignable', error);
  }

  const token = typeof data?.access_token === 'string' ? data.access_token : '';
  if (!token) {
    const error = typeof data?.error === 'string' ? data.error : 'upstream';
    if (error === 'authorization_pending') return json({ ok: true, status: 'pending' });
    if (error === 'slow_down') return json({ ok: true, status: 'slow_down' });
    if (error === 'expired_token') {
      await env.DB.prepare('DELETE FROM github_pending WHERE id = ?').bind(id).run();
      return json({ ok: true, status: 'expired' });
    }
    if (error === 'access_denied') {
      await env.DB.prepare('DELETE FROM github_pending WHERE id = ?').bind(id).run();
      return json({ ok: true, status: 'denied' });
    }
    if (error === 'incorrect_client_credentials' || error === 'device_flow_disabled') {
      console.error('GitHub OAuth mal configuré', error);
      return fail(
        503,
        'not_configured',
        'La connexion GitHub du relais est mal configurée (identifiants ou device flow).',
      );
    }
    console.error('GitHub token a répondu', error);
    return fail(502, 'upstream', 'GitHub a refusé la connexion.');
  }

  const viewer = await githubViewer(token);
  if (!viewer.ok) return fail(502, 'upstream', 'Le compte GitHub n’a pas pu être lu.');
  await saveGithubAccount(env, user.id, viewer.login, token, typeof data.scope === 'string' ? data.scope : '');
  await env.DB.prepare('DELETE FROM github_pending WHERE id = ?').bind(id).run();
  return json({ ok: true, status: 'connected', login: viewer.login });
}

/** Connexion manuelle : la personne colle un jeton d'accès personnel. */
async function githubTokenRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const payload = await request.json().catch(() => null);
  const token = typeof payload?.token === 'string' ? payload.token.trim() : '';
  if (!/^(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})$/.test(token)) {
    return fail(400, 'bad_token', 'Ce texte ne ressemble pas à un jeton GitHub.');
  }
  const viewer = await githubViewer(token);
  if (!viewer.ok) {
    return fail(400, 'bad_token', 'GitHub refuse ce jeton : expiré, révoqué ou sans les bons droits.');
  }
  await saveGithubAccount(env, user.id, viewer.login, token, '');
  return json({ ok: true, login: viewer.login });
}

async function githubReposRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const account = await githubAccount(env, user.id);
  if (!account) return fail(400, 'not_connected', 'Connecte ton compte GitHub d’abord.');
  const r = await gh(
    { GITHUB_TOKEN: account.token },
    '/user/repos?sort=updated&per_page=100&affiliation=owner,collaborator,organization_member',
  );
  if (!r.ok) return fail(502, 'upstream', 'La liste des dépôts n’a pas pu être lue.');
  const repos = (Array.isArray(r.data) ? r.data : []).map((item) => ({
    full_name: item.full_name,
    private: Boolean(item.private),
    default_branch: item.default_branch,
    can_push: Boolean(item.permissions?.push),
  }));
  return json({ ok: true, repos });
}

async function githubRepoRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const account = await githubAccount(env, user.id);
  if (!account) return fail(400, 'not_connected', 'Connecte ton compte GitHub d’abord.');
  const payload = await request.json().catch(() => null);
  const raw = typeof payload?.repo === 'string' ? payload.repo.trim() : '';
  if (!raw) {
    await env.DB.prepare('UPDATE github_accounts SET default_repo = "", updated_at = ? WHERE user_id = ?')
      .bind(Date.now(), user.id)
      .run();
    return json({ ok: true, defaultRepo: '' });
  }
  const repo = /^[\w.-]+\/[\w.-]+$/.test(raw) ? raw : `${account.login}/${raw}`;
  const check = await gh({ GITHUB_TOKEN: account.token }, `/repos/${repo}`);
  if (!check.ok) return fail(400, 'bad_repo', 'Ce dépôt est introuvable ou inaccessible avec ce compte.');
  const fullName = check.data?.full_name || repo;
  await env.DB.prepare('UPDATE github_accounts SET default_repo = ?, updated_at = ? WHERE user_id = ?')
    .bind(fullName, Date.now(), user.id)
    .run();
  return json({ ok: true, defaultRepo: fullName });
}

async function githubDisconnectRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  await env.DB.prepare('DELETE FROM github_accounts WHERE user_id = ?').bind(user.id).run();
  await env.DB.prepare('DELETE FROM github_pending WHERE user_id = ?').bind(user.id).run();
  return json({ ok: true });
}

/* --------------------------------------------------------- Sites de test */
// L’IA publie une page HTML autonome par site, servie publiquement sous
// /s/<slug>. Le slug est aléatoire donc difficile à deviner, et le rendu est
// isolé du relais par une politique sandbox : les scripts de la page tournent
// dans une origine unique, sans accès aux données ni aux sessions.

function siteUrl(origin, slug) {
  return `${origin}/s/${slug}`;
}

function siteMissingPage() {
  return new Response(
    '<!doctype html><html lang="fr"><head><meta charset="utf-8">' +
      '<meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<title>Site introuvable</title><style>' +
      'body{margin:0;min-height:100vh;display:flex;align-items:center;' +
      'justify-content:center;background:#0b0912;color:#e9e6f5;' +
      'font:15px/1.6 system-ui,sans-serif;padding:24px;text-align:center}' +
      'p{color:#a9a4c0}</style></head><body><main>' +
      '<h1>Site introuvable</h1>' +
      '<p>Cette adresse ne correspond à aucun site publié.</p>' +
      '</main></body></html>',
    {
      status: 404,
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
      },
    },
  );
}

async function publicSiteRoute(env, slug) {
  if (!env.DB) return siteMissingPage();
  await ensureSchema(env.DB);
  const row = await env.DB.prepare('SELECT html FROM sites WHERE slug = ?')
    .bind(slug)
    .first();
  if (!row || typeof row.html !== 'string') return siteMissingPage();
  return new Response(row.html, {
    status: 200,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'public, max-age=60',
      'content-security-policy': 'sandbox allow-scripts allow-forms allow-popups allow-modals',
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
    },
  });
}

function readSiteHtml(payload) {
  const html = typeof payload?.html === 'string' ? payload.html : '';
  if (!html.trim()) return { error: 'Le contenu HTML du site est vide.' };
  if (html.length > MAX_SITE_HTML_CHARS) {
    return { error: 'Page trop lourde : 300 000 caractères maximum.' };
  }
  return { html };
}

function readSiteTitle(payload, fallback = '') {
  const raw = typeof payload?.title === 'string' ? payload.title.trim() : '';
  return (raw || fallback).slice(0, 120);
}

async function countSites(env, userId) {
  const row = await env.DB.prepare('SELECT COUNT(*) AS total FROM sites WHERE user_id = ?')
    .bind(userId)
    .first();
  return Number(row?.total) || 0;
}

async function createSite(env, userId, origin, payload) {
  const read = readSiteHtml(payload);
  if (read.error) return read;
  if ((await countSites(env, userId)) >= MAX_SITES_PER_USER) {
    return {
      error: `Limite de ${MAX_SITES_PER_USER} sites atteinte : supprime un site avant d’en créer un autre.`,
    };
  }
  const slug = randomHex(9);
  const title = readSiteTitle(payload);
  const now = Date.now();
  await env.DB.prepare(
    'INSERT INTO sites (slug, user_id, title, html, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
  )
    .bind(slug, userId, title, read.html, now, now)
    .run();
  return { slug, title, url: siteUrl(origin, slug), updatedAt: now };
}

async function updateSite(env, userId, slug, payload) {
  const read = readSiteHtml(payload);
  if (read.error) return read;
  const row = await env.DB.prepare('SELECT title FROM sites WHERE slug = ? AND user_id = ?')
    .bind(slug, userId)
    .first();
  if (!row) return { error: 'Ce site n’existe pas, ou il ne t’appartient pas.' };
  const title = readSiteTitle(payload, row.title || '');
  await env.DB.prepare(
    'UPDATE sites SET title = ?, html = ?, updated_at = ? WHERE slug = ? AND user_id = ?',
  )
    .bind(title, read.html, Date.now(), slug, userId)
    .run();
  return { slug, title };
}

async function deleteSite(env, userId, slug) {
  const row = await env.DB.prepare('SELECT title FROM sites WHERE slug = ? AND user_id = ?')
    .bind(slug, userId)
    .first();
  if (!row) return { error: 'Ce site n’existe pas, ou il ne t’appartient pas.' };
  await env.DB.prepare('DELETE FROM sites WHERE slug = ? AND user_id = ?')
    .bind(slug, userId)
    .run();
  return { slug, title: row.title || '' };
}

async function listSites(env, userId, origin) {
  const { results } = await env.DB.prepare(
    'SELECT slug, title, updated_at FROM sites WHERE user_id = ? ORDER BY updated_at DESC LIMIT 100',
  )
    .bind(userId)
    .all();
  return (Array.isArray(results) ? results : []).map((row) => ({
    slug: row.slug,
    title: row.title || '',
    url: siteUrl(origin, row.slug),
    updatedAt: row.updated_at,
  }));
}

/** Exécute un outil de site et renvoie { result, summary, ok }. */
async function runSiteTool(ctx, name, args) {
  const a = args && typeof args === 'object' ? args : {};
  const { env, userId, origin } = ctx;

  if (name === 'site_create') {
    const site = await createSite(env, userId, origin, a);
    if (site.error) return { ok: false, summary: 'Création refusée', result: { error: site.error } };
    return {
      ok: true,
      summary: `Site « ${site.title || site.slug} » publié`,
      result: {
        slug: site.slug,
        title: site.title,
        url: site.url,
        note: 'Donne cette adresse à la personne : elle s’ouvre dans un navigateur.',
      },
    };
  }

  if (name === 'site_update') {
    const slug = typeof a.slug === 'string' ? a.slug.trim() : '';
    if (!slug) {
      return { ok: false, summary: 'Site non précisé', result: { error: 'Indique le « slug » du site à modifier.' } };
    }
    const site = await updateSite(env, userId, slug, a);
    if (site.error) return { ok: false, summary: 'Mise à jour refusée', result: { error: site.error } };
    return {
      ok: true,
      summary: `Site « ${site.title || slug} » mis à jour`,
      result: { slug, title: site.title, url: siteUrl(origin, slug) },
    };
  }

  if (name === 'site_list') {
    const sites = await listSites(env, userId, origin);
    return {
      ok: true,
      summary: `${sites.length} site(s) publié(s)`,
      result: { sites },
    };
  }

  if (name === 'site_delete') {
    const slug = typeof a.slug === 'string' ? a.slug.trim() : '';
    if (!slug) {
      return { ok: false, summary: 'Site non précisé', result: { error: 'Indique le « slug » du site à supprimer.' } };
    }
    const site = await deleteSite(env, userId, slug);
    if (site.error) return { ok: false, summary: 'Suppression refusée', result: { error: site.error } };
    return { ok: true, summary: `Site « ${site.title || slug} » supprimé`, result: { slug } };
  }

  return { ok: false, summary: `Outil inconnu : ${name}`, result: { error: 'Outil inconnu.' } };
}

async function listSitesRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const sites = await listSites(env, user.id, new URL(request.url).origin);
  return json({ ok: true, sites });
}

async function createSiteRoute(request, env) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const payload = await request.json().catch(() => null);
  const site = await createSite(env, user.id, new URL(request.url).origin, payload);
  if (site.error) return fail(400, 'bad_request', site.error);
  return json({ ok: true, site });
}

async function updateSiteRoute(request, env, slug) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const payload = await request.json().catch(() => null);
  const site = await updateSite(env, user.id, slug, payload);
  if (site.error) return fail(404, 'not_found', site.error);
  return json({ ok: true, slug: site.slug, title: site.title, url: siteUrl(new URL(request.url).origin, slug) });
}

async function deleteSiteRoute(request, env, slug) {
  if (!env.DB) return fail(503, 'not_ready', 'Le service de comptes n’est pas prêt.');
  const user = await signedIn(request, env);
  if (!user) return fail(401, 'unauthorized', 'Connexion requise.');
  const site = await deleteSite(env, user.id, slug);
  if (site.error) return fail(404, 'not_found', site.error);
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
      return statusPage(Boolean(env.GROQ_API_KEY), githubConfigured(env) || githubOauthConfigured(env));
    }

    if (url.pathname === '/health') {
      return json({
        ok: true,
        configured: Boolean(env.GROQ_API_KEY),
        github: githubConfigured(env) || githubOauthConfigured(env),
        githubOauth: githubOauthConfigured(env),
        sites: true,
      });
    }

    if (url.pathname === '/github') {
      if (request.method === 'GET') return githubStatusRoute(request, env);
      if (request.method === 'PATCH' || request.method === 'PUT') return githubRepoRoute(request, env);
      if (request.method === 'DELETE') return githubDisconnectRoute(request, env);
      return fail(405, 'method', 'Utilise GET, PATCH ou DELETE.');
    }

    if (url.pathname === '/github/device') {
      if (request.method !== 'POST') return fail(405, 'method', 'Utilise POST.');
      return githubDeviceStartRoute(request, env);
    }

    if (url.pathname === '/github/device/poll') {
      if (request.method !== 'POST') return fail(405, 'method', 'Utilise POST.');
      return githubDevicePollRoute(request, env);
    }

    if (url.pathname === '/github/token') {
      if (request.method !== 'POST') return fail(405, 'method', 'Utilise POST.');
      return githubTokenRoute(request, env);
    }

    if (url.pathname === '/github/repos') {
      if (request.method !== 'GET') return fail(405, 'method', 'Utilise GET.');
      return githubReposRoute(request, env);
    }

    if (url.pathname.startsWith('/s/')) {
      if (request.method !== 'GET') return fail(405, 'method', 'Utilise GET.');
      const slug = url.pathname.slice(3).replace(/\/+$/, '').trim();
      if (!SITE_SLUG_RE.test(slug)) return siteMissingPage();
      return publicSiteRoute(env, slug);
    }

    if (url.pathname === '/sites') {
      if (request.method === 'GET') return listSitesRoute(request, env);
      if (request.method === 'POST') return createSiteRoute(request, env);
      return fail(405, 'method', 'Utilise GET ou POST.');
    }

    if (url.pathname.startsWith('/sites/')) {
      const slug = (url.pathname.split('/').filter(Boolean)[1] || '').trim();
      if (!SITE_SLUG_RE.test(slug)) return fail(404, 'not_found', 'Site introuvable.');
      if (request.method === 'PATCH' || request.method === 'PUT')
        return updateSiteRoute(request, env, slug);
      if (request.method === 'DELETE') return deleteSiteRoute(request, env, slug);
      return fail(405, 'method', 'Utilise PATCH ou DELETE.');
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
