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

  /** Check-in / "Je suis en sécurité" */
  checkIn: () => isEnabled("FEATURE_CHECK_IN", true),
  /** Trajet sécurisé + ETA + auto-alerte */
  safeTrip: () => isEnabled("FEATURE_SAFE_TRIP", true),
  /** Statut live (position + batterie) pendant SOS */
  liveStatus: () => isEnabled("FEATURE_LIVE_STATUS", true),
  /** Zones de confiance (domicile / travail / école) */
  trustZones: () => isEnabled("FEATURE_TRUST_ZONES", true),
  /** Veille de quartier + digest */
  neighborhoodWatch: () => isEnabled("FEATURE_NEIGHBORHOOD_WATCH", true),
  /** Preuves photo/audio sur signalements */
  witnessEvidence: () => isEnabled("FEATURE_WITNESS_EVIDENCE", true),
  /** Score de fiabilité des signalements */
  reliabilityScore: () => isEnabled("FEATURE_RELIABILITY_SCORE", true),
  /** Mode escorte (suivi live jusqu'à arrivée) */
  escortMode: () => isEnabled("FEATURE_ESCORT_MODE", true),
  /** Dispatch terrain (assignation agent, chat, clôture) */
  fieldDispatch: () => isEnabled("FEATURE_FIELD_DISPATCH", true),
  /** Alerte géofence secteur aux leaders */
  sectorGeofence: () => isEnabled("FEATURE_SECTOR_GEOFENCE", true),
  /** Tableau de bord ops temps réel */
  opsDashboard: () => isEnabled("FEATURE_OPS_DASHBOARD", true),
  /** Rapports automatiques hebdo PDF/CSV */
  autoReports: () => isEnabled("FEATURE_AUTO_REPORTS", true),
  /** Webhooks partenaires SOS/incidents */
  partnerWebhooks: () => isEnabled("FEATURE_PARTNER_WEBHOOKS", true),
  /** Abonnement premium (stub, feature-flagged) */
  premium: () => isEnabled("FEATURE_PREMIUM", false),
  /** Sauvegarde chiffrée des contacts */
  contactBackup: () => isEnabled("FEATURE_CONTACT_BACKUP", true),
  /** File hors-ligne étendue (rapports + messages groupe) */
  offlineQueue: () => isEnabled("FEATURE_OFFLINE_QUEUE", true),
  /** Invitation cercle par code / QR / deep link */
  circleInvite: () => isEnabled("FEATURE_CIRCLE_INVITE", true),
  /** Partage public SOS/trajet (liens à durée limitée) */
  publicShare: () => isEnabled("FEATURE_PUBLIC_SHARE", true),
  /** Ping sécurité planifié « Tu es OK ? » */
  safetyPing: () => isEnabled("FEATURE_SAFETY_PING", true),
  /** Alertes groupe structurées (coupure, inondation…) */
  structuredGroupAlerts: () => isEnabled("FEATURE_STRUCTURED_GROUP_ALERTS", true),
  /** Corridors / repères locaux + suggestion d'itinéraire */
  corridors: () => isEnabled("FEATURE_CORRIDORS", true),
  /** Carte de chaleur (UI mobile) — API reste disponible */
  heatmap: () => isEnabled("FEATURE_HEATMAP", false),

  /** Mode maintenance / bannière dégradée (kill switch soft) */
  maintenanceMode: () => isEnabled("FEATURE_MAINTENANCE_MODE", false),
  /** Kill switch SOS (false = SOS désactivé côté API + app) */
  sosEnabled: () => isEnabled("FEATURE_SOS_ENABLED", true),

  isEnabled,
};
