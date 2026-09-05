const { pool } = require("../config/database");
const { writeAudit } = require("../services/audit");

const SLUG_RE = /^[a-z][a-z0-9_]{1,49}$/;

const clientIp = (req) =>
  req.headers["x-forwarded-for"]?.toString().split(",")[0]?.trim() || req.ip;

function slugify(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_|_$/g, "")
    .slice(0, 50);
}

function normalizeSlug(raw, { required = true } = {}) {
  const slug = slugify(raw);
  if (!slug) return required ? null : "";
  if (!SLUG_RE.test(slug)) return null;
  return slug;
}

/** Public catalog for the mobile report form + filters (active + reportable). */
const listPublic = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT slug, label_fr, sort_order
       FROM incident_types
       WHERE active = true AND reportable = true
       ORDER BY sort_order ASC, label_fr ASC`
    );
    return res.json({ data: result.rows });
  } catch (err) {
    console.error("listPublic incident types error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/** Staff catalog (includes inactive + SOS). */
const listStaff = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, slug, label_fr, active, sort_order, reportable, system, created_at, updated_at
       FROM incident_types
       ORDER BY sort_order ASC, label_fr ASC`
    );
    return res.json({ data: result.rows });
  } catch (err) {
    console.error("listStaff incident types error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const createType = async (req, res) => {
  const { label_fr, slug: rawSlug, active, sort_order, reportable } = req.body;
  const label = String(label_fr || "").trim();
  if (label.length < 2) {
    return res.status(400).json({ error: "Libellé requis (2 caractères minimum)" });
  }
  const slug = normalizeSlug(rawSlug || label);
  if (!slug) {
    return res.status(400).json({ error: "Identifiant invalide (lettres, chiffres, _ )" });
  }
  const sort = Number.parseInt(sort_order, 10);
  try {
    const result = await pool.query(
      `INSERT INTO incident_types (slug, label_fr, active, sort_order, reportable)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [
        slug,
        label,
        active !== false,
        Number.isFinite(sort) ? sort : 100,
        reportable !== false,
      ]
    );
    await writeAudit({
      actorId: req.userId,
      action: "incident_type.create",
      entityType: "incident_type",
      entityId: result.rows[0].id,
      metadata: { slug, label_fr: label },
      ip: clientIp(req),
    });
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    if (err.code === "23505") {
      return res.status(409).json({ error: "Cet identifiant existe déjà" });
    }
    console.error("create incident type error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const updateType = async (req, res) => {
  const { id } = req.params;
  const { label_fr, active, sort_order, reportable } = req.body;
  const label = label_fr !== undefined ? String(label_fr).trim() : null;
  if (label !== null && label.length < 2) {
    return res.status(400).json({ error: "Libellé requis (2 caractères minimum)" });
  }
  const sort =
    sort_order === undefined || sort_order === null || sort_order === ""
      ? null
      : Number.parseInt(sort_order, 10);
  if (sort !== null && !Number.isFinite(sort)) {
    return res.status(400).json({ error: "Ordre d'affichage invalide" });
  }
  try {
    const result = await pool.query(
      `UPDATE incident_types SET
        label_fr = COALESCE($1, label_fr),
        active = COALESCE($2, active),
        sort_order = COALESCE($3, sort_order),
        reportable = COALESCE($4, reportable),
        updated_at = NOW()
       WHERE id = $5
       RETURNING *`,
      [label, active === undefined ? null : Boolean(active), sort, reportable === undefined ? null : Boolean(reportable), id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Type introuvable" });
    }
    await writeAudit({
      actorId: req.userId,
      action: "incident_type.update",
      entityType: "incident_type",
      entityId: id,
      metadata: { slug: result.rows[0].slug },
      ip: clientIp(req),
    });
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("update incident type error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const deleteType = async (req, res) => {
  const { id } = req.params;
  try {
    const existing = await pool.query(
      `SELECT id, slug, system FROM incident_types WHERE id = $1`,
      [id]
    );
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: "Type introuvable" });
    }
    const row = existing.rows[0];
    if (row.system) {
      return res.status(400).json({ error: "Ce type système ne peut pas être supprimé" });
    }
    const used = await pool.query(
      `SELECT COUNT(*)::int AS n FROM incidents WHERE incident_type = $1`,
      [row.slug]
    );
    if (used.rows[0].n > 0) {
      const deactivated = await pool.query(
        `UPDATE incident_types SET active = false, updated_at = NOW()
         WHERE id = $1 RETURNING *`,
        [id]
      );
      await writeAudit({
        actorId: req.userId,
        action: "incident_type.deactivate",
        entityType: "incident_type",
        entityId: id,
        metadata: { slug: row.slug, reason: "in_use" },
        ip: clientIp(req),
      });
      return res.json({
        message: "Type utilisé : désactivé (les signalements existants restent valides)",
        deactivated: true,
        data: deactivated.rows[0],
      });
    }
    await pool.query(`DELETE FROM incident_types WHERE id = $1`, [id]);
    await writeAudit({
      actorId: req.userId,
      action: "incident_type.delete",
      entityType: "incident_type",
      entityId: id,
      metadata: { slug: row.slug },
      ip: clientIp(req),
    });
    return res.json({ message: "Type supprimé", deleted: true, id });
  } catch (err) {
    console.error("delete incident type error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = {
  listPublic,
  listStaff,
  createType,
  updateType,
  deleteType,
  slugify,
};
