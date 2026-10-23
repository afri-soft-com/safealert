const { pool } = require("../config/database");
const {
  DEFAULT_PRIVACY_BODY,
  DEFAULT_PRIVACY_TITLE,
  DEFAULT_PRIVACY_VERSION,
} = require("./privacyDefaults");

const CLE_TITLE = "LEGAL_PRIVACY_TITLE";
const CLE_VERSION = "LEGAL_PRIVACY_VERSION";
const CLE_BODY = "LEGAL_PRIVACY_BODY";
const CLE_FORMAT = "LEGAL_PRIVACY_FORMAT";

const upsertKey = async (key, value) => {
  await pool.query(
    `INSERT INTO app_settings (key, value, updated_at)
     VALUES ($1, $2, NOW())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`,
    [key, value]
  );
};

const readMap = async () => {
  try {
    const r = await pool.query(
      `SELECT key, value FROM app_settings
       WHERE key IN ($1, $2, $3, $4)`,
      [CLE_TITLE, CLE_VERSION, CLE_BODY, CLE_FORMAT]
    );
    return Object.fromEntries(r.rows.map((row) => [row.key, row.value]));
  } catch (err) {
    if (err.code !== "42P01") {
      console.error("privacySettings read:", err.message);
    }
    return {};
  }
};

/** Idempotent — seed defaults if body key is missing. */
const ensurePrivacyDefaults = async () => {
  try {
    const exist = await pool.query(
      `SELECT 1 FROM app_settings WHERE key = $1 LIMIT 1`,
      [CLE_BODY]
    );
    if (exist.rows.length > 0) return;
    await upsertKey(CLE_TITLE, DEFAULT_PRIVACY_TITLE);
    await upsertKey(CLE_VERSION, DEFAULT_PRIVACY_VERSION);
    await upsertKey(CLE_BODY, DEFAULT_PRIVACY_BODY);
    await upsertKey(CLE_FORMAT, "markdown");
  } catch (err) {
    if (err.code !== "42P01") {
      console.error("privacySettings ensure:", err.message);
    }
  }
};

const getPublishedPrivacy = async () => {
  await ensurePrivacyDefaults();
  const map = await readMap();
  const body = (map[CLE_BODY] || "").trim();
  if (!body) {
    return {
      slug: "privacy",
      title: DEFAULT_PRIVACY_TITLE,
      version: DEFAULT_PRIVACY_VERSION,
      body: DEFAULT_PRIVACY_BODY,
      format: "markdown",
      source: "fallback",
    };
  }
  return {
    slug: "privacy",
    title: (map[CLE_TITLE] || "").trim() || DEFAULT_PRIVACY_TITLE,
    version: (map[CLE_VERSION] || "").trim() || DEFAULT_PRIVACY_VERSION,
    body,
    format: (map[CLE_FORMAT] || "").trim() || "markdown",
    source: "database",
  };
};

const savePrivacy = async ({ title, version, body, format } = {}) => {
  const nextTitle = String(title ?? DEFAULT_PRIVACY_TITLE).trim() || DEFAULT_PRIVACY_TITLE;
  const nextVersion =
    String(version ?? DEFAULT_PRIVACY_VERSION).trim() || DEFAULT_PRIVACY_VERSION;
  const nextBody = String(body ?? "").trim();
  if (!nextBody) {
    const err = new Error("Le texte de la politique est obligatoire.");
    err.status = 400;
    throw err;
  }
  if (nextBody.length > 200_000) {
    const err = new Error("Texte trop long.");
    err.status = 400;
    throw err;
  }
  const nextFormat = String(format ?? "markdown").trim().toLowerCase() || "markdown";
  if (!["markdown", "html", "plain"].includes(nextFormat)) {
    const err = new Error("Format invalide (markdown, html ou plain).");
    err.status = 400;
    throw err;
  }

  await upsertKey(CLE_TITLE, nextTitle);
  await upsertKey(CLE_VERSION, nextVersion);
  await upsertKey(CLE_BODY, nextBody);
  await upsertKey(CLE_FORMAT, nextFormat);

  return {
    slug: "privacy",
    title: nextTitle,
    version: nextVersion,
    body: nextBody,
    format: nextFormat,
    source: "database",
  };
};

module.exports = {
  CLE_TITLE,
  CLE_VERSION,
  CLE_BODY,
  CLE_FORMAT,
  ensurePrivacyDefaults,
  getPublishedPrivacy,
  savePrivacy,
};
