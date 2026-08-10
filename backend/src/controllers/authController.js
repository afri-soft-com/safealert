const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { pool } = require("../config/database");
const { sendSMS, isSMSConfigured } = require("../services/sms");
const { normalizePhone } = require("../utils/phone");
const { log } = require("../utils/logger");
const { incrPhoneOtp } = require("../config/redis");
const { otpPhoneLimit } = require("../config/features");

const OTP_TTL_SECONDS = 300;
const OTP_PHONE_MAX = Number(process.env.OTP_PHONE_MAX_PER_WINDOW || 5);

/**
 * Temporary OTP bypass for admin testing without working SMS.
 * SECURITY: never enable by default. Only when ALLOW_DEV_OTP=true
 * (or OTP_BYPASS_ENABLED=true). Prefer also leaving SMS keys empty so
 * codes are not dual-path; either way, DISABLE this flag as soon as
 * Twilio/SerdiPay delivery works — otherwise OTP leaks in API + logs.
 */
const isDevOtpBypassEnabled = () =>
  process.env.ALLOW_DEV_OTP === "true" ||
  process.env.OTP_BYPASS_ENABLED === "true";

/** Expose OTP in API/logs: local/dev without SMS, or explicit flag (incl. prod). */
const shouldExposeDevOtp = () =>
  isDevOtpBypassEnabled() ||
  (process.env.NODE_ENV !== "production" && !isSMSConfigured());

const requestCode = async (req, res) => {
  const phone = normalizePhone(req.body.phone);
  if (!phone) return res.status(400).json({ error: "Numéro de téléphone invalide" });

  try {
    if (otpPhoneLimit()) {
      const count = await incrPhoneOtp(phone);
      if (count !== null && count > OTP_PHONE_MAX) {
        return res.status(429).json({
          error: "Trop de codes demandés pour ce numéro, réessayez dans 15 minutes",
        });
      }
      // Fallback DB si Redis absent
      if (count === null) {
        const recent = await pool.query(
          `SELECT COUNT(*)::int AS n FROM otp_codes
           WHERE phone = $1 AND created_at > NOW() - INTERVAL '15 minutes'`,
          [phone]
        );
        if ((recent.rows[0]?.n ?? 0) >= OTP_PHONE_MAX) {
          return res.status(429).json({
            error: "Trop de codes demandés pour ce numéro, réessayez dans 15 minutes",
          });
        }
      }
    }

    // Invalider les codes non utilisés (conserver l'historique pour le rate-limit téléphone)
    await pool.query(
      `UPDATE otp_codes SET used_at = NOW()
       WHERE phone = $1 AND used_at IS NULL`,
      [phone]
    );
    await pool.query(
      "DELETE FROM otp_codes WHERE expires_at < NOW() - INTERVAL '1 hour'"
    );

    // Prefer random OTP; optional OTP_BYPASS_CODE only when bypass flag is on
    const bypassFixed =
      isDevOtpBypassEnabled() && process.env.OTP_BYPASS_CODE
        ? String(process.env.OTP_BYPASS_CODE).replace(/\D/g, "").slice(0, 6)
        : "";
    const code =
      bypassFixed.length === 6
        ? bypassFixed
        : String(Math.floor(100000 + Math.random() * 900000));
    const codeHash = await bcrypt.hash(code, 10);
    const expiresAt = new Date(Date.now() + OTP_TTL_SECONDS * 1000);

    await pool.query(
      "INSERT INTO otp_codes (phone, code_hash, expires_at) VALUES ($1, $2, $3)",
      [phone, codeHash, expiresAt]
    );

    await sendSMS(phone, `Votre code SafeAlert: ${code}. Valide 5 minutes.`);

    const exposeDevOtp = shouldExposeDevOtp();

    if (exposeDevOtp) {
      // console.warn so Render (and other hosts) always surface this in logs
      console.warn("");
      console.warn("══════════════════════════════════════════════");
      console.warn(`  [DEV OTP] ${phone} → ${code}  (valide 5 min)`);
      console.warn("  SMS non configuré — bypass temporaire (ALLOW_DEV_OTP).");
      console.warn("  DÉSACTIVER dès que Twilio/SerdiPay est en place.");
      console.warn("══════════════════════════════════════════════");
      console.warn("");
      log(`[DEV OTP] ${phone} → ${code}`);
    }

    const payload = { message: "Code envoyé", expiresIn: OTP_TTL_SECONDS };
    if (exposeDevOtp) {
      payload.devCode = code;
    }

    return res.json(payload);
  } catch (err) {
    console.error("requestCode error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const verifyCode = async (req, res) => {
  const phone = normalizePhone(req.body.phone);
  const { code, pseudo } = req.body;
  if (!phone || !code) {
    return res.status(400).json({ error: "Téléphone et code requis" });
  }

  try {
    const otpResult = await pool.query(
      `SELECT id, code_hash FROM otp_codes
       WHERE phone = $1 AND used_at IS NULL AND expires_at > NOW()
       ORDER BY created_at DESC LIMIT 1`,
      [phone]
    );

    if (otpResult.rows.length === 0) {
      return res.status(401).json({ error: "Code invalide ou expiré" });
    }

    const otpRow = otpResult.rows[0];
    const valid = await bcrypt.compare(String(code), otpRow.code_hash);
    if (!valid) {
      return res.status(401).json({ error: "Code invalide ou expiré" });
    }

    // Resolve user before consuming OTP so a missing pseudo can be retried
    // with the same code (admin-web and mobile first-login flows).
    let user = await pool.query("SELECT * FROM users WHERE phone = $1", [phone]);

    if (user.rows.length === 0) {
      if (!pseudo || !String(pseudo).trim()) {
        return res.status(400).json({ error: "Pseudo requis pour créer un compte" });
      }

      const adminPhone = (process.env.PLATFORM_ADMIN_PHONE || "").trim();
      const role =
        adminPhone && phone === normalizePhone(adminPhone)
          ? "platform_admin"
          : "citizen";

      await pool.query("UPDATE otp_codes SET used_at = NOW() WHERE id = $1", [otpRow.id]);

      const result = await pool.query(
        "INSERT INTO users (phone, pseudo, role) VALUES ($1, $2, $3) RETURNING *",
        [phone, String(pseudo).trim(), role]
      );
      user = result.rows[0];
    } else {
      await pool.query("UPDATE otp_codes SET used_at = NOW() WHERE id = $1", [otpRow.id]);
      user = user.rows[0];
    }

    const token = jwt.sign(
      { userId: user.id, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN || "30d" }
    );

    return res.json({
      token,
      user: {
        id: user.id,
        phone: user.phone,
        pseudo: user.pseudo,
        role: user.role,
        sector_name: user.sector_name ?? null,
        is_discreet_mode: user.is_discreet_mode ?? false,
        share_presence: user.share_presence ?? true,
        sos_notify_groups: user.sos_notify_groups ?? true,
      },
    });
  } catch (err) {
    console.error("verifyCode error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const getProfile = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, phone, pseudo, role, sector_name, avatar_url, is_discreet_mode, share_presence,
              sos_notify_groups, last_seen_at, created_at
       FROM users WHERE id = $1`,
      [req.userId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: "Utilisateur non trouvé" });
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("getProfile error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const updateProfile = async (req, res) => {
  const { pseudo, avatar_url, is_discreet_mode, share_presence, sos_notify_groups } = req.body;
  try {
    const result = await pool.query(
      `UPDATE users SET
        pseudo = COALESCE($1, pseudo),
        avatar_url = COALESCE($2, avatar_url),
        is_discreet_mode = COALESCE($3, is_discreet_mode),
        share_presence = COALESCE($4, share_presence),
        sos_notify_groups = COALESCE($5, sos_notify_groups),
        updated_at = NOW()
       WHERE id = $6 RETURNING id, phone, pseudo, role, avatar_url, is_discreet_mode, share_presence, sos_notify_groups`,
      [pseudo, avatar_url, is_discreet_mode, share_presence, sos_notify_groups, req.userId]
    );
    return res.json(result.rows[0]);
  } catch (err) {
    console.error("updateProfile error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const updatePosition = async (req, res) => {
  const { lat, lng } = req.body;
  if (lat == null || lng == null) {
    return res.status(400).json({ error: "Latitude et longitude requises" });
  }
  try {
    const userRes = await pool.query("SELECT share_presence FROM users WHERE id = $1", [req.userId]);
    if (userRes.rows.length === 0) {
      return res.status(404).json({ error: "Utilisateur non trouvé" });
    }
    if (userRes.rows[0].share_presence === false) {
      return res.json({ message: "Partage de présence désactivé" });
    }

    await pool.query(
      `UPDATE users SET last_lat = $1, last_lng = $2, last_seen_at = NOW(), updated_at = NOW()
       WHERE id = $3`,
      [lat, lng, req.userId]
    );
    return res.json({ message: "Position mise à jour" });
  } catch (err) {
    console.error("updatePosition error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const updateFCMToken = async (req, res) => {
  const { fcm_token } = req.body;
  if (!fcm_token) return res.status(400).json({ error: "FCM token requis" });
  try {
    await pool.query("UPDATE users SET fcm_token = $1, updated_at = NOW() WHERE id = $2", [fcm_token, req.userId]);
    return res.json({ message: "Token mis à jour" });
  } catch (err) {
    console.error("updateFCMToken error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

const deleteAccount = async (req, res) => {
  try {
    await pool.query("DELETE FROM otp_codes WHERE phone = (SELECT phone FROM users WHERE id = $1)", [req.userId]);
    await pool.query("DELETE FROM incidents WHERE user_id = $1", [req.userId]);
    await pool.query("DELETE FROM trust_contacts WHERE user_id = $1 OR contact_phone = (SELECT phone FROM users WHERE id = $1)", [req.userId]);
    await pool.query("DELETE FROM users WHERE id = $1", [req.userId]);
    return res.json({ message: "Compte supprimé" });
  } catch (err) {
    console.error("deleteAccount error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = {
  requestCode,
  verifyCode,
  getProfile,
  updateProfile,
  updatePosition,
  updateFCMToken,
  deleteAccount,
};
