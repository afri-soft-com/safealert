const { pool } = require("../config/database");
const { notifyTrustContacts } = require("../services/alert");

/** Hours before the same user can trigger another low-battery message. */
const COOLDOWN_HOURS = 6;
/** Highest level the app may report as "almost empty". */
const MAX_PCT = 10;

/**
 * POST /api/battery/low { lat, lng, battery_pct }
 *
 * Sent by the app when the phone is almost empty during a secured trip or an
 * SOS. Trust contacts get the last position before the phone dies. Only sent
 * while a trip or SOS is active, and at most once per COOLDOWN_HOURS.
 */
const reportLowBattery = async (req, res) => {
  const pct = Number(req.body?.battery_pct);
  if (!Number.isFinite(pct) || pct < 0 || pct > MAX_PCT) {
    return res.status(400).json({ error: `Niveau de batterie invalide (0 à ${MAX_PCT} %).` });
  }
  let lat = Number(req.body?.lat);
  let lng = Number(req.body?.lng);
  const hasPos =
    Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;

  try {
    const active = await pool.query(
      `SELECT
         EXISTS (SELECT 1 FROM safe_trips WHERE user_id = $1 AND status = 'active') AS trip,
         EXISTS (
           SELECT 1 FROM incidents
           WHERE user_id = $1 AND status = 'active'
             AND incident_type IN ('sos','sos_discret')
             AND created_at > NOW() - INTERVAL '6 hours'
         ) AS sos`,
      [req.userId]
    );
    const { trip, sos } = active.rows[0] || {};
    if (!trip && !sos) {
      return res.json({ notified: false, reason: "no_active_trip_or_sos" });
    }

    // Claim the cooldown atomically so two quick calls send one message.
    const claimed = await pool.query(
      `UPDATE users SET low_battery_notified_at = NOW()
       WHERE id = $1
         AND (low_battery_notified_at IS NULL
              OR low_battery_notified_at < NOW() - make_interval(hours => $2))
       RETURNING last_lat, last_lng`,
      [req.userId, COOLDOWN_HOURS]
    );
    if (claimed.rows.length === 0) {
      return res.json({ notified: false, reason: "cooldown" });
    }
    if (!hasPos) {
      lat = claimed.rows[0].last_lat;
      lng = claimed.rows[0].last_lng;
    }

    const level = Math.round(pct);
    const stats = await notifyTrustContacts(
      req.userId,
      lat,
      lng,
      "low_battery",
      (user, where, maps) => ({
        title: "🪫 Batterie presque vide",
        body: `Le téléphone de ${user.pseudo} est à ${level} % ${sos ? "pendant un SOS" : "pendant un trajet"}. Dernière position : ${where}`,
        sms: `SafeAlert : le telephone de ${user.pseudo} est a ${level} pourcent ${sos ? "pendant un SOS" : "pendant un trajet"} et va bientot s eteindre. Derniere position : ${where} ${maps}`,
      }),
      { battery_pct: String(level) }
    );
    return res.json({ notified: true, contacts: stats.contacts });
  } catch (err) {
    console.error("reportLowBattery error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { reportLowBattery, COOLDOWN_HOURS, MAX_PCT };
