const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { neighborhoodWatch } = require("../config/features");
const { sendSMS, isSMSConfigured } = require("../services/sms");
const { resolvePlace } = require("../utils/incidentZone");

const DIGEST_MINUTE_SLOTS = [0, 15, 30, 45];
const DEFAULT_RADIUS_M = 5000;
const MIN_RADIUS_M = 500;
const MAX_RADIUS_M = 30000;

/** Parse digest hour 0–23. `0` is valid (midnight). Invalid → null. */
function parseDigestHour(value) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n) || n < 0 || n > 23) return null;
  return n;
}

/** Parse digest minute — only 0 / 15 / 30 / 45. Default 0 when omitted. */
function parseDigestMinute(value, { required = false } = {}) {
  if (value === undefined || value === null || value === "") {
    return required ? null : 0;
  }
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n) || !DIGEST_MINUTE_SLOTS.includes(n)) return null;
  return n;
}

function parseRadiusM(value) {
  if (value === undefined || value === null || value === "") return DEFAULT_RADIUS_M;
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n)) return DEFAULT_RADIUS_M;
  return Math.min(Math.max(n, MIN_RADIUS_M), MAX_RADIUS_M);
}

function parseCoord(value) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number.parseFloat(value);
  if (!Number.isFinite(n)) return null;
  return n;
}

/** Current hour + minute in Africa/Kinshasa (UTC+1, no DST). */
function kinshasaParts(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Africa/Kinshasa",
    hour: "numeric",
    minute: "numeric",
    hourCycle: "h23",
  }).formatToParts(date);
  const hourRaw = parts.find((p) => p.type === "hour")?.value;
  const minuteRaw = parts.find((p) => p.type === "minute")?.value;
  const hour = Number.parseInt(hourRaw, 10);
  const minute = Number.parseInt(minuteRaw, 10);
  return {
    hour: Number.isFinite(hour) ? hour % 24 : 0,
    minute: Number.isFinite(minute) ? minute % 60 : 0,
  };
}

function kinshasaHour(date = new Date()) {
  return kinshasaParts(date).hour;
}

function minuteSlot(minute) {
  const m = Number.isFinite(minute) ? minute : 0;
  return Math.floor(m / 15) * 15;
}

function normalizeQuartier(q) {
  return String(q || "")
    .trim()
    .replace(/\s+/g, " ");
}

function normalizeCity(c) {
  const s = normalizeQuartier(c);
  return s.length >= 2 ? s : null;
}

/**
 * Scope filter:
 * - With GPS: incidents within radius (disambiguates same names in other cities).
 * - Without GPS: quartier name + city when available.
 */
function buildIncidentScope(scope) {
  const raw =
    scope && typeof scope === "object" && !Array.isArray(scope)
      ? scope
      : { quartier: scope };
  const q = normalizeQuartier(raw.quartier);
  const city = normalizeCity(raw.city);
  const lat = parseCoord(raw.lat);
  const lng = parseCoord(raw.lng);
  const radius = parseRadiusM(raw.radius_m);
  const qPattern = `%${q}%`;
  const cityPattern = city ? `%${city}%` : null;

  if (lat != null && lng != null) {
    return {
      q,
      city,
      lat,
      lng,
      radius_m: radius,
      mode: "radius",
      sql: `(
        i.lat IS NOT NULL AND i.lng IS NOT NULL
        AND (
          6371000 * acos(LEAST(1.0, GREATEST(-1.0,
            cos(radians($lat)) * cos(radians(i.lat))
            * cos(radians(i.lng) - radians($lng))
            + sin(radians($lat)) * sin(radians(i.lat))
          )))
        ) <= $radius
      )`,
      params: { lat, lng, radius },
    };
  }

  // Name + city disambiguation (legacy / no GPS)
  let sql = `i.zone_name ILIKE $qPattern`;
  const params = { qPattern };
  if (cityPattern) {
    sql = `(
      i.zone_name ILIKE $qPattern
      AND (
        i.zone_city ILIKE $cityPattern
        OR i.zone_name ILIKE $cityPattern
      )
    )`;
    params.cityPattern = cityPattern;
  }
  return {
    q,
    city,
    lat: null,
    lng: null,
    radius_m: null,
    mode: city ? "name_city" : "name",
    sql,
    params,
  };
}

function bindScopeSql(sql, params, startIdx = 1) {
  const values = [];
  let idx = startIdx;
  let out = sql;
  const order = ["lat", "lng", "radius", "qPattern", "cityPattern"];
  for (const key of order) {
    if (!(key in params) || params[key] === undefined) continue;
    const token = `$${key}`;
    if (!out.includes(token)) continue;
    out = out.split(token).join(`$${idx}`);
    values.push(params[key]);
    idx += 1;
  }
  return { sql: out, values, nextIdx: idx };
}

async function loadDigestPayload(scopeInput, { hours = 24, limit = 50 } = {}) {
  const scope =
    typeof scopeInput === "string"
      ? buildIncidentScope({ quartier: scopeInput })
      : buildIncidentScope(scopeInput || {});

  if (!scope.q || scope.q.length < 2) {
    throw Object.assign(new Error("Nom de quartier requis"), { status: 400 });
  }

  const h = Math.min(Math.max(Number.parseInt(hours, 10) || 24, 1), 168);
  const lim = Math.min(Math.max(Number.parseInt(limit, 10) || 50, 1), 100);

  const bound = bindScopeSql(scope.sql, scope.params, 1);
  const hoursIdx = bound.nextIdx;
  const limitIdx = hoursIdx + 1;
  const where = `${bound.sql} AND i.created_at > NOW() - ($${hoursIdx}::int * INTERVAL '1 hour')`;
  const statsParams = [...bound.values, h];

  const [stats, byType, bySeverity, incidents] = await Promise.all([
    pool.query(
      `SELECT COUNT(*)::int AS total,
              COUNT(*) FILTER (
                WHERE severity = 'alert' OR incident_type IN ('sos', 'sos_discret')
              )::int AS sos,
              COUNT(*) FILTER (WHERE severity = 'warning')::int AS warnings,
              COUNT(*) FILTER (WHERE severity = 'info' OR severity IS NULL)::int AS info
       FROM incidents i
       WHERE ${where}`,
      statsParams
    ),
    pool.query(
      `SELECT incident_type AS type, COUNT(*)::int AS count
       FROM incidents i
       WHERE ${where}
       GROUP BY incident_type
       ORDER BY count DESC`,
      statsParams
    ),
    pool.query(
      `SELECT COALESCE(severity, 'info') AS severity, COUNT(*)::int AS count
       FROM incidents i
       WHERE ${where}
       GROUP BY COALESCE(severity, 'info')
       ORDER BY count DESC`,
      statsParams
    ),
    pool.query(
      `SELECT i.id, i.incident_type, i.description, i.severity, i.zone_name, i.zone_city,
              i.lat, i.lng, i.created_at
       FROM incidents i
       WHERE ${where}
       ORDER BY i.created_at DESC
       LIMIT $${limitIdx}`,
      [...statsParams, lim]
    ),
  ]);

  const { total, sos, warnings, info } = stats.rows[0];
  return {
    quartier: scope.q,
    city: scope.city,
    lat: scope.lat,
    lng: scope.lng,
    radius_m: scope.radius_m,
    match_mode: scope.mode,
    window_hours: h,
    generated_at: new Date().toISOString(),
    summary: {
      total,
      sos,
      warnings,
      info,
      by_type: byType.rows,
      by_severity: bySeverity.rows,
    },
    incidents: incidents.rows,
  };
}

async function deliverDigest(sub) {
  const payload = await loadDigestPayload(sub);
  const q = payload.quartier;
  const city = payload.city;
  const { total, sos } = payload.summary;
  const title = city ? `Digest — ${q} (${city})` : `Digest — ${q}`;
  const body = `${total} incident(s) dont ${sos} SOS sur 24h.`;
  let delivered = false;

  if (sub.fcm_token) {
    try {
      await sendPush(sub.fcm_token, {
        notification: { title: `🏘️ ${title}`, body },
        data: {
          type: "neighborhood_digest",
          quartier: q,
          city: city || "",
          subscription_id: sub.id ? String(sub.id) : "",
          total: String(total),
          sos: String(sos),
          window_hours: "24",
        },
      });
      delivered = true;
    } catch (err) {
      console.error("neighborhood push error:", err.message);
    }
  }

  if (!delivered && isSMSConfigured() && sub.phone) {
    try {
      await sendSMS(sub.phone, `SafeAlert ${title}: ${body}`);
      delivered = true;
    } catch (err) {
      console.error("neighborhood sms error:", err.message);
    }
  }

  if (delivered) {
    await pool.query(
      `UPDATE neighborhood_subscriptions SET last_digest_at = NOW() WHERE id = $1`,
      [sub.id]
    );
  }
  return { delivered, title, body, total, sos, payload };
}

const getDigest = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  try {
    let scope = {
      quartier: req.query.quartier,
      city: req.query.city,
      lat: req.query.lat,
      lng: req.query.lng,
      radius_m: req.query.radius_m,
    };

    const subId = (req.query.subscription_id || "").toString().trim();
    if (subId) {
      const sub = await pool.query(
        `SELECT * FROM neighborhood_subscriptions WHERE id = $1 AND user_id = $2`,
        [subId, req.userId]
      );
      if (sub.rows.length === 0) {
        return res.status(404).json({ error: "Abonnement introuvable" });
      }
      scope = sub.rows[0];
    }

    const digest = await loadDigestPayload(scope, {
      hours: req.query.hours,
      limit: req.query.limit,
    });
    return res.json(digest);
  } catch (err) {
    if (err.status === 400) {
      return res.status(400).json({ error: err.message });
    }
    console.error("neighborhood getDigest error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const subscribe = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  let q = normalizeQuartier(req.body.quartier);
  let city = normalizeCity(req.body.city);
  let lat = parseCoord(req.body.lat);
  let lng = parseCoord(req.body.lng);
  const radius = parseRadiusM(req.body.radius_m);

  const hour =
    req.body.digest_hour === undefined ||
    req.body.digest_hour === null ||
    req.body.digest_hour === ""
      ? 18
      : parseDigestHour(req.body.digest_hour);
  if (hour === null) {
    return res.status(400).json({ error: "Heure du résumé invalide (0–23)" });
  }
  const minute = parseDigestMinute(req.body.digest_minute);
  if (minute === null) {
    return res.status(400).json({ error: "Minutes invalides (0, 15, 30 ou 45)" });
  }

  // GPS → resolve city / suggest quartier to disambiguate homonyms.
  if (lat != null && lng != null) {
    const place = await resolvePlace(lat, lng);
    if (!city && place.city) city = normalizeCity(place.city);
    if ((!q || q.length < 2) && place.zoneName) q = normalizeQuartier(place.zoneName);
  }

  if (!q || q.length < 2) {
    return res.status(400).json({
      error: "Nom de quartier requis (ou activez le GPS pour le détecter).",
    });
  }
  if (lat == null || lng == null) {
    return res.status(400).json({
      error:
        "Position GPS requise pour éviter les homonymes (ex. même quartier dans une autre ville).",
    });
  }

  try {
    const result = await pool.query(
      `INSERT INTO neighborhood_subscriptions
         (user_id, quartier, city, lat, lng, radius_m, digest_hour, digest_minute)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT (user_id, quartier) DO UPDATE
         SET digest_hour = EXCLUDED.digest_hour,
             digest_minute = EXCLUDED.digest_minute,
             city = EXCLUDED.city,
             lat = EXCLUDED.lat,
             lng = EXCLUDED.lng,
             radius_m = EXCLUDED.radius_m
       RETURNING *`,
      [req.userId, q, city, lat, lng, radius, hour, minute]
    );
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("neighborhood subscribe error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const updateSubscription = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  if (req.body.digest_hour === undefined || req.body.digest_hour === null || req.body.digest_hour === "") {
    return res.status(400).json({ error: "Heure du résumé requise (0–23)" });
  }
  const hour = parseDigestHour(req.body.digest_hour);
  if (hour === null) {
    return res.status(400).json({ error: "Heure du résumé invalide (0–23)" });
  }
  const minute = parseDigestMinute(req.body.digest_minute);
  if (minute === null) {
    return res.status(400).json({ error: "Minutes invalides (0, 15, 30 ou 45)" });
  }

  const city =
    req.body.city !== undefined ? normalizeCity(req.body.city) : undefined;
  const lat = req.body.lat !== undefined ? parseCoord(req.body.lat) : undefined;
  const lng = req.body.lng !== undefined ? parseCoord(req.body.lng) : undefined;
  const radius =
    req.body.radius_m !== undefined ? parseRadiusM(req.body.radius_m) : undefined;

  try {
    const result = await pool.query(
      `UPDATE neighborhood_subscriptions
       SET digest_hour = $1,
           digest_minute = $2,
           city = COALESCE($3, city),
           lat = COALESCE($4, lat),
           lng = COALESCE($5, lng),
           radius_m = COALESCE($6, radius_m)
       WHERE id = $7 AND user_id = $8 RETURNING *`,
      [
        hour,
        minute,
        city === undefined ? null : city,
        lat === undefined ? null : lat,
        lng === undefined ? null : lng,
        radius === undefined ? null : radius,
        req.params.id,
        req.userId,
      ]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Abonnement introuvable" });
    }
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("neighborhood update error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const unsubscribe = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  try {
    await pool.query(
      `DELETE FROM neighborhood_subscriptions WHERE id = $1 AND user_id = $2`,
      [req.params.id, req.userId]
    );
    return res.json({ message: "Désabonnement effectué" });
  } catch (err) {
    console.error("neighborhood unsubscribe error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const listSubscriptions = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM neighborhood_subscriptions WHERE user_id = $1 ORDER BY created_at DESC`,
      [req.userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("listSubscriptions error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const sendNow = async (req, res) => {
  if (!neighborhoodWatch()) {
    return res.status(503).json({ error: "Veille de quartier désactivée" });
  }
  try {
    const sub = await pool.query(
      `SELECT ns.*, u.fcm_token, u.phone
       FROM neighborhood_subscriptions ns
       JOIN users u ON u.id = ns.user_id
       WHERE ns.id = $1 AND ns.user_id = $2`,
      [req.params.id, req.userId]
    );
    if (sub.rows.length === 0) {
      return res.status(404).json({ error: "Abonnement introuvable" });
    }
    const result = await deliverDigest(sub.rows[0]);
    if (!result.delivered) {
      return res.status(502).json({
        error:
          "Résumé non envoyé : activez les notifications push (ou SMS) sur cet appareil.",
      });
    }
    return res.json({
      message: "Résumé envoyé",
      total: result.total,
      sos: result.sos,
      body: result.body,
    });
  } catch (err) {
    console.error("neighborhood sendNow error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const sendDigests = async (date = new Date()) => {
  if (!neighborhoodWatch()) return { sent: 0 };
  const { hour, minute } = kinshasaParts(date);
  const slot = minuteSlot(minute);
  const subs = await pool.query(
    `SELECT ns.*, u.fcm_token, u.phone FROM neighborhood_subscriptions ns
     JOIN users u ON u.id = ns.user_id
     WHERE ns.digest_hour = $1
       AND COALESCE(ns.digest_minute, 0) = $2
       AND (ns.last_digest_at IS NULL OR ns.last_digest_at < NOW() - INTERVAL '20 hours')`,
    [hour, slot]
  );

  let sent = 0;
  for (const sub of subs.rows) {
    const result = await deliverDigest(sub);
    if (result.delivered) sent += 1;
  }
  return { sent, hour, minute: slot };
};

module.exports = {
  subscribe,
  updateSubscription,
  unsubscribe,
  listSubscriptions,
  sendNow,
  getDigest,
  sendDigests,
  loadDigestPayload,
  buildIncidentScope,
  parseDigestHour,
  parseDigestMinute,
  parseRadiusM,
  kinshasaHour,
  kinshasaParts,
  minuteSlot,
  normalizeQuartier,
  DIGEST_MINUTE_SLOTS,
  DEFAULT_RADIUS_M,
};
