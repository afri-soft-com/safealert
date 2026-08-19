const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { sendSMS } = require("../services/sms");
const { checkIn: checkInEnabled } = require("../config/features");

const notifyTrustCircle = async (userId, title, body, dataType, smsBody) => {
  const userRes = await pool.query("SELECT pseudo FROM users WHERE id = $1", [userId]);
  const pseudo = userRes.rows[0]?.pseudo || "Un contact";
  const contacts = await pool.query(
    `SELECT tc.contact_phone, u.fcm_token, u.id as contact_user_id
     FROM trust_contacts tc
     LEFT JOIN users u ON tc.contact_phone = u.phone
     WHERE tc.user_id = $1`,
    [userId]
  );

  for (const c of contacts.rows) {
    try {
      if (c.fcm_token) {
        await sendPush(c.fcm_token, {
          notification: { title, body: body.replace("{pseudo}", pseudo) },
          data: { type: dataType, userId: String(userId) },
        });
      }
      if (smsBody) {
        await sendSMS(c.contact_phone, smsBody.replace("{pseudo}", pseudo));
      }
    } catch (err) {
      console.error("notifyTrustCircle contact failed:", err.message);
    }
  }
  return { contactsNotified: contacts.rows.length, pseudo };
};

/** POST /api/checkin — "Je suis en sécurité" */
const createCheckIn = async (req, res) => {
  if (!checkInEnabled()) {
    return res.status(503).json({ error: "Check-in désactivé" });
  }

  const { lat, lng, message, incident_id, trip_id } = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO check_ins (user_id, incident_id, trip_id, lat, lng, message)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
      [req.userId, incident_id || null, trip_id || null, lat || null, lng || null, message || null]
    );

    if (incident_id) {
      await pool.query(
        `UPDATE incidents SET status = 'resolved', resolved_at = NOW(),
           close_reason = COALESCE(close_reason, 'check_in_safe')
         WHERE id = $1 AND user_id = $2 AND status IN ('active','acknowledged','in_progress')`,
        [incident_id, req.userId]
      );
    }

    const notify = await notifyTrustCircle(
      req.userId,
      "✅ SafeAlert — En sécurité",
      "{pseudo} confirme : je suis en sécurité.",
      "check_in_safe",
      "✅ SafeAlert — {pseudo} confirme être en sécurité."
    );

    const io = req.app.get("io");
    if (io) {
      io.emit("check_in", {
        user_id: req.userId,
        check_in: result.rows[0],
        pseudo: notify.pseudo,
      });
    }

    return res.status(201).json({ check_in: result.rows[0], notification: notify });
  } catch (err) {
    console.error("createCheckIn error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const listMyCheckIns = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM check_ins WHERE user_id = $1 ORDER BY created_at DESC LIMIT 30`,
      [req.userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("listMyCheckIns error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { createCheckIn, listMyCheckIns, notifyTrustCircle };
