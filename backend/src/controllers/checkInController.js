const { pool } = require("../config/database");
const { sendSMS } = require("../services/sms");
const { checkIn: checkInEnabled } = require("../config/features");
const { notifyUserGroupsOnSafe } = require("../services/groupNotify");
const { phoneLookupVariants } = require("../utils/phone");
const { sendPushToUser } = require("../services/pushTargets");

/** FCM data payload values must be strings. */
const asFcmData = (obj = {}) => {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v == null || v === "") continue;
    out[k] = String(v);
  }
  return out;
};

const notifyTrustCircle = async (userId, title, body, dataType, smsBody, extraData = {}) => {
  const userRes = await pool.query("SELECT pseudo FROM users WHERE id = $1", [userId]);
  const pseudo = userRes.rows[0]?.pseudo || "Un contact";
  const contacts = await pool.query(
    `SELECT contact_name, contact_phone FROM trust_contacts WHERE user_id = $1`,
    [userId]
  );

  let pushSent = 0;
  let smsSent = 0;
  for (const c of contacts.rows) {
    try {
      const variants = phoneLookupVariants(c.contact_phone);
      let contactUserId = null;
      if (variants.length) {
        const matched = await pool.query(
          `SELECT id FROM users WHERE phone = ANY($1::text[]) LIMIT 1`,
          [variants]
        );
        contactUserId = matched.rows[0]?.id || null;
      }
      if (contactUserId && String(contactUserId) !== String(userId)) {
        const n = await sendPushToUser(contactUserId, {
          notification: { title, body: body.replace("{pseudo}", pseudo) },
          data: {
            type: dataType,
            userId: String(userId),
            ...asFcmData(extraData),
          },
        });
        if (n > 0) pushSent += 1;
      }
      if (smsBody && c.contact_phone) {
        const smsRes = await sendSMS(c.contact_phone, smsBody.replace("{pseudo}", pseudo));
        if (smsRes && !smsRes.simulated && !smsRes.failed) smsSent += 1;
      }
    } catch (err) {
      console.error("notifyTrustCircle contact failed:", err.message);
    }
  }
  return {
    contactsNotified: contacts.rows.length,
    contactsPush: pushSent,
    contactsSms: smsSent,
    pseudo,
  };
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
    try {
      notify.groupSos = await notifyUserGroupsOnSafe(
        req.userId,
        lat || null,
        lng || null,
        notify.pseudo,
        null,
        io
      );
    } catch (groupErr) {
      console.error("notifyUserGroupsOnSafe error:", groupErr.message);
      notify.groupSos = { error: true };
    }

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
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
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
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { createCheckIn, listMyCheckIns, notifyTrustCircle };
