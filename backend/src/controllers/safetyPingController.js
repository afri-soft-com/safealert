const { pool } = require("../config/database");
const { safetyPing } = require("../config/features");
const { sendPush } = require("../config/firebase");
const { notifyTrustCircle } = require("./checkInController");
const { notifyGroupMembers } = require("../services/groupNotify");

const assertEnabled = (res) => {
  if (!safetyPing()) {
    res.status(503).json({ error: "Ping sécurité désactivé" });
    return false;
  }
  return true;
};

/** Schedule a "Tu es OK ?" ping — silence after window → notify circle */
const schedulePing = async (req, res) => {
  if (!assertEnabled(res)) return;
  const inMinutes = Math.min(Math.max(parseInt(req.body?.in_minutes) || 60, 5), 24 * 60);
  const windowMinutes = Math.min(Math.max(parseInt(req.body?.window_minutes) || 15, 5), 60);
  const notifyGroups = req.body?.notify_groups === true;

  try {
    // Cancel previous pending pings for this user
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
    return res.status(500).json({ error: "Erreur serveur" });
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
    return res.status(500).json({ error: "Erreur serveur" });
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
    return res.status(500).json({ error: "Erreur serveur" });
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
    return res.status(500).json({ error: "Erreur serveur" });
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
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

/** Reminder when due_at reached (ask user) + escalate after window */
const processSafetyPings = async () => {
  if (!safetyPing()) return { reminded: 0, missed: 0 };

  // Remind users whose due_at just passed (within last 2 min) — once via FCM
  const due = await pool.query(
    `SELECT sp.*, u.fcm_token, u.pseudo FROM safety_pings sp
     JOIN users u ON u.id = sp.user_id
     WHERE sp.status = 'pending'
       AND sp.due_at <= NOW()
       AND sp.due_at > NOW() - INTERVAL '2 minutes'
       AND sp.responded_at IS NULL`
  );
  let reminded = 0;
  for (const ping of due.rows) {
    if (ping.fcm_token) {
      await sendPush(ping.fcm_token, {
        notification: {
          title: "SafeAlert — Tu es OK ?",
          body: "Confirmez rapidement que tout va bien.",
        },
        data: { type: "safety_ping_ask", pingId: String(ping.id) },
      });
      reminded += 1;
    }
  }

  // Missed: due_at + window_minutes passed
  const missed = await pool.query(
    `SELECT * FROM safety_pings
     WHERE status = 'pending'
       AND due_at + (window_minutes * INTERVAL '1 minute') < NOW()`
  );
  let missedCount = 0;
  for (const ping of missed.rows) {
    await pool.query(
      `UPDATE safety_pings SET status = 'missed' WHERE id = $1`,
      [ping.id]
    );
    await notifyTrustCircle(
      ping.user_id,
      "⚠️ SafeAlert — Pas de réponse",
      "{pseudo} n'a pas confirmé être OK à temps. Contactez-le/la.",
      "safety_ping_missed",
      "⚠️ SafeAlert — {pseudo} n'a pas répondu au contrôle sécurité."
    );

    if (ping.notify_groups) {
      const groups = await pool.query(
        `SELECT group_id FROM group_members WHERE user_id = $1`,
        [ping.user_id]
      );
      const user = await pool.query(`SELECT pseudo FROM users WHERE id = $1`, [ping.user_id]);
      const pseudo = user.rows[0]?.pseudo || "Un membre";
      for (const g of groups.rows) {
        await notifyGroupMembers(
          g.group_id,
          ping.user_id,
          {
            title: "⚠️ Contrôle sécurité",
            body: `${pseudo} n'a pas confirmé être OK`,
          },
          { type: "safety_ping_missed", pingId: String(ping.id) }
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
