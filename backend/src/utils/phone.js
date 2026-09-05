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

/**
 * Variants of a number for DB lookup (E.164, local 0…, national 9 digits, 243…).
 * Avoids "user missing" when the stored phone was not normalized the same way.
 */
const phoneLookupVariants = (raw) => {
  const variants = new Set();
  const push = (v) => {
    if (v == null) return;
    const s = String(v).trim();
    if (s) variants.add(s);
  };
  push(raw);
  const normalized = normalizePhone(raw);
  push(normalized);
  if (normalized && normalized.startsWith("+243") && normalized.length === 13) {
    const national = normalized.slice(4);
    push(national);
    push(`0${national}`);
    push(`243${national}`);
    push(`+243${national}`);
  }
  return Array.from(variants);
};

module.exports = { normalizePhone, phoneLookupVariants };
