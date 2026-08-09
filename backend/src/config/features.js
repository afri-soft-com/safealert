/** Feature flags (env FEATURE_* = true|1|yes). */
const isEnabled = (name, defaultValue = false) => {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return defaultValue;
  return ["1", "true", "yes", "on"].includes(String(raw).toLowerCase());
};

module.exports = {
  socketRedisAdapter: () => isEnabled("FEATURE_SOCKET_REDIS_ADAPTER", true),
  auditLog: () => isEnabled("FEATURE_AUDIT_LOG", true),
  otpPhoneLimit: () => isEnabled("FEATURE_OTP_PHONE_LIMIT", true),
  isEnabled,
};
