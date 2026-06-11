/**
 * Normalize phone numbers to E.164 for DRC (+243) and international input.
 * Strips spaces, dashes, and common local prefixes so request/verify always match.
 */
const normalizePhone = (raw) => {
  if (raw == null) return null;
  let phone = String(raw).trim().replace(/[\s\-().]/g, "");
  if (!phone) return null;

  if (phone.startsWith("00")) {
    phone = `+${phone.slice(2)}`;
  } else if (phone.startsWith("0") && !phone.startsWith("+")) {
    phone = `+243${phone.slice(1)}`;
  } else if (/^243\d{9}$/.test(phone)) {
    phone = `+${phone}`;
  } else if (/^\d{9}$/.test(phone)) {
    phone = `+243${phone}`;
  }

  if (!/^\+\d{10,15}$/.test(phone)) return null;
  return phone;
};

module.exports = { normalizePhone };
