const { pool } = require("../config/database");
const { safetyPing } = require("../config/features");
const { sendPushToUser } = require("../services/pushTargets");
const { notifyTrustCircle } = require("./checkInController");
const { notifyGroupMembers } = require("../services/groupNotify");

const assertEnabled = (res) => {
  if (!safetyPing()) {
    res.status(503).json({ error: "Ping sécurité désactivé" });
    return false;
  }
  return true;
};

/** Last known location only if the user allows presence sharing. */
const loadEmitterProfile = async (userId) => {
  const result = await pool.query(
    `SELECT pseudo, phone, share_presence, last_lat, last_lng
     FROM users WHERE id = $1`,
    [userId]
  );
  const u = result.rows[0] || {};
  const share = u.share_presence !== false;
  const lat = share && u.last_lat != null ? Number(u.last_lat) : null;
  const lng = share && u.last_lng != null ? Number(u.last_lng) : null;
  return {
    pseudo: u.pseudo || "Un contact",
    phone: u.phone ? String(u.phone) : "",
    lat: Number.isFinite(lat) ? lat : null,
    lng: Number.isFinite(lng) ? lng : null,
  };
};

const missPushData = (ping, profile, groupId = null) => {
  const data = {
    type: "safety_ping_missed",
    pingId: String(ping.id),
    userId: String(ping.user_id),
    pseudo: profile.pseudo,
  };
  if (profile.phone) data.phone = profile.phone;
  if (profile.lat != null) data.lat = String(profile.lat);
  if (profile.lng != null) data.lng = String(profile.lng);
  if (groupId) data.groupId = String(groupId);
  return data;
};

/** Schedule a "Tu es OK ?" ping — silence after window → notify circle */
const schedulePing = async (req, res) => {
  if (!assertEnabled(res)) return;
  // Min 1 min for QA; max 24h
  const inMinutes = Math.min(Math.max(parseInt(req.body?.in_minutes, 10) || 60, 1), 24 * 60);
  const windowMinutes = Math.min(Math.max(parseInt(req.body?.window_minutes, 10) || 15, 1), 60);
  const notifyGroups = req.body?.notify_groups === true;

  try {
    await pool.query(
      `UPDATE safety_pings SET status = 'cancelled'
       WHERE user_id = $1 AND status = 'pending'`,
      [req.userId]
    );

    const result = await pool.query(
      `INSERT INTO safety_pings (user_id, due_at, window_minutes, notify_groups, message)
       VALUES ($1, NOW() + ($2 * INTERVAL '1 minute'), $3, $4, $5)
       RETURNING *`,
      [req.userId, inMinutes, windowMinutes, notifyGroups, req.body?.message || null]
    );

    return res.status(201).json({ ping: result.rows[0] });
  } catch (err) {
    console.error("schedulePing error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const respondOk = async (req, res) => {
  if (!assertEnabled(res)) return;
  const { id } = req.params;
  try {
    const result = await pool.query(
      `UPDATE safety_pings SET status = 'ok', responded_at = NOW()
       WHERE id = $1 AND user_id = $2 AND status = 'pending'
       RETURNING *`,
      [id, req.userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Ping introuvable ou déjà traité" });
    }

    await notifyTrustCircle(
      req.userId,
      "✅ SafeAlert — Tout va bien",
      "{pseudo} a confirmé être OK.",
      "safety_ping_ok",
      null
    );

    return res.json({ ping: result.rows[0] });
  } catch (err) {
    console.error("respondOk error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const cancelPing = async (req, res) => {
  if (!assertEnabled(res)) return;
  try {
    const result = await pool.query(
      `UPDATE safety_pings SET status = 'cancelled'
       WHERE id = $1 AND user_id = $2 AND status = 'pending'
       RETURNING *`,
      [req.params.id, req.userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Ping introuvable" });
    }
    return res.json({ ping: result.rows[0] });
  } catch (err) {
    console.error("cancelPing error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const listMyPings = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM safety_pings WHERE user_id = $1
       ORDER BY created_at DESC LIMIT 20`,
      [req.userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("listMyPings error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const getActivePing = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM safety_pings
       WHERE user_id = $1 AND status = 'pending'
       ORDER BY due_at ASC LIMIT 1`,
      [req.userId]
    );
    return res.json(result.rows[0] || {});
  } catch (err) {
    console.error("getActivePing error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/**
 * Reminder when due_at reached (ask user) + escalate after window.
 * @param {import('socket.io').Server | null} io
 */
const processSafetyPings = async (io = null) => {
  if (!safetyPing()) return { reminded: 0, missed: 0 };

  // Ask once: due reached and not yet reminded (no 2-minute race with cron)
  const due = await pool.query(
    `SELECT sp.id, sp.user_id FROM safety_pings sp
     WHERE sp.status = 'pending'
       AND sp.due_at <= NOW()
       AND sp.reminded_at IS NULL
       AND sp.responded_at IS NULL`
  );
  let reminded = 0;
  for (const ping of due.rows) {
    const marked = await pool.query(
      `UPDATE safety_pings SET reminded_at = NOW()
       WHERE id = $1 AND status = 'pending' AND reminded_at IS NULL
       RETURNING id`,
      [ping.id]
    );
    if (marked.rows.length === 0) continue;

    const n = await sendPushToUser(ping.user_id, {
      notification: {
        title: "SafeAlert — Tu es OK ?",
        body: "Confirmez rapidement que tout va bien.",
      },
      data: { type: "safety_ping_ask", pingId: String(ping.id) },
    });
    if (n > 0) reminded += 1;
  }

  // Missed: due_at + window_minutes passed → trust circle (+ groups if opted in)
  const missed = await pool.query(
    `SELECT * FROM safety_pings
     WHERE status = 'pending'
       AND due_at + (window_minutes * INTERVAL '1 minute') < NOW()`
  );
  let missedCount = 0;
  for (const ping of missed.rows) {
    const marked = await pool.query(
      `UPDATE safety_pings SET status = 'missed' WHERE id = $1 AND status = 'pending'
       RETURNING id`,
      [ping.id]
    );
    if (marked.rows.length === 0) continue;

    const profile = await loadEmitterProfile(ping.user_id);
    const missExtra = {
      pseudo: profile.pseudo,
      phone: profile.phone || undefined,
      lat: profile.lat != null ? profile.lat : undefined,
      lng: profile.lng != null ? profile.lng : undefined,
    };

    await notifyTrustCircle(
      ping.user_id,
      "⚠️ SafeAlert — Pas de réponse",
      "{pseudo} n'a pas confirmé être OK à temps. Contactez-le/la.",
      "safety_ping_missed",
      "⚠️ SafeAlert — {pseudo} n'a pas répondu au contrôle sécurité.",
      missExtra
    );

    if (ping.notify_groups) {
      const groups = await pool.query(
        `SELECT group_id FROM group_members WHERE user_id = $1`,
        [ping.user_id]
      );
      const pseudo = profile.pseudo || "Un membre";
      for (const g of groups.rows) {
        try {
          await pool.query(
            `INSERT INTO group_alerts (group_id, author_id, type, title, body, lat, lng)
             VALUES ($1, $2, 'danger', $3, $4, $5, $6)`,
            [
              g.group_id,
              ping.user_id,
              `Contrôle sécurité — ${pseudo}`,
              `${pseudo} n'a pas confirmé être OK à temps. Contactez-le/la.`,
              profile.lat,
              profile.lng,
            ]
          );
        } catch (err) {
          console.error("safety ping group_alerts insert:", err.message);
        }
        await notifyGroupMembers(
          g.group_id,
          ping.user_id,
          {
            title: "⚠️ Contrôle sécurité",
            body: `${pseudo} n'a pas confirmé être OK`,
          },
          missPushData(ping, profile, g.group_id),
          io,
          { sms: true }
        );
      }
    }
    missedCount += 1;
  }

  return { reminded, missed: missedCount };
};

module.exports = {
  schedulePing,
  respondOk,
  cancelPing,
  listMyPings,
  getActivePing,
  processSafetyPings,
};
