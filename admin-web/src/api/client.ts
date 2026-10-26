export const API_BASE =
  import.meta.env.VITE_API_BASE_URL?.replace(/\/$/, "") || "/api";

const TOKEN_KEY = "safealert_admin_token";
const USER_KEY = "safealert_admin_user";

export type UserRole = "citizen" | "leader" | "agent" | "admin" | "platform_admin";

export function isStaffRole(role?: string | null): boolean {
  return role === "admin" || role === "platform_admin";
}

export function isSuperAdmin(role?: string | null): boolean {
  return role === "platform_admin";
}

export interface AuthUser {
  id: string;
  phone: string | null;
  email?: string | null;
  pseudo: string;
  role: UserRole;
  sector_name: string | null;
}

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY);
}

export function getStoredUser(): AuthUser | null {
  const raw = localStorage.getItem(USER_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as AuthUser;
  } catch {
    return null;
  }
}

export function saveSession(token: string, user: AuthUser) {
  localStorage.setItem(TOKEN_KEY, token);
  localStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function clearSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}

export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = getToken();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string>),
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${API_BASE}${path}`, { ...options, headers });
  const body = await res.json().catch(() => ({}));

  if (!res.ok) {
    const raw = typeof body.error === "string" ? body.error.trim() : "";
    const technical =
      !raw ||
      /exception|sql|postgres|redis|econnrefused|internal server|stack/i.test(raw) ||
      /^erreur\s+\d{3}$/i.test(raw);
    const message = technical
      ? statusMessage(res.status) || "Une erreur est survenue. Réessayez."
      : raw;
    throw new ApiError(message, res.status);
  }
  return body as T;
}

function statusMessage(status: number): string {
  switch (status) {
    case 400:
      return "Demande invalide. Vérifiez les informations saisies.";
    case 401:
      return "Session expirée. Veuillez vous reconnecter.";
    case 403:
      return "Accès non autorisé pour votre profil.";
    case 404:
      return "Élément introuvable.";
    case 429:
      return "Trop de tentatives. Réessayez dans quelques instants.";
    case 500:
    case 502:
    case 503:
    case 504:
      return "Service temporairement indisponible. Réessayez plus tard.";
    default:
      return "";
  }
}

async function downloadAuthenticated(path: string, filename: string): Promise<void> {
  const token = getToken();
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${API_BASE}${path}`, { headers });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const raw = typeof body.error === "string" ? body.error : "";
    throw new ApiError(
      statusMessage(res.status) || raw || "Téléchargement impossible",
      res.status
    );
  }
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export const api = {
  requestCode: (phone: string) =>
    request<{
      message: string;
      expiresIn?: number;
      smsEnvoye?: boolean;
      devCode?: string;
      codeOtp?: string;
    }>("/auth/request-code", {
      method: "POST",
      body: JSON.stringify({ phone }),
    }),

  verifyCode: (phone: string, code: string, pseudo?: string) =>
    request<{ token: string; user: AuthUser }>("/auth/verify-code", {
      method: "POST",
      body: JSON.stringify({
        phone,
        code,
        isNewAccount: Boolean(pseudo?.trim()),
        ...(pseudo?.trim() ? { pseudo: pseudo.trim() } : {}),
      }),
    }),

  googleLogin: (idToken: string) =>
    request<{ token: string; user: AuthUser; isNew?: boolean; needsPinSetup?: boolean }>("/auth/google", {
      method: "POST",
      body: JSON.stringify({ idToken }),
    }),

  getStats: () =>
    request<{
      users: number;
      incidents: number;
      active_incidents: number;
      active_partners: number;
      groups: number;
    }>("/admin/stats"),

  getProfile: () => request<AuthUser>("/auth/profile"),

  getAppConfig: () =>
    request<{
      maintenance: boolean;
      sosEnabled: boolean;
      maintenanceBanner: string;
    }>("/app/config"),

  getSettings: () =>
    request<{
      maintenance: boolean;
      maintenance_message: string;
      is_super_admin: boolean;
    }>("/admin/settings"),

  setMaintenance: (enabled: boolean, message?: string) =>
    request<{ maintenance: boolean; maintenance_message: string }>(
      "/admin/settings/maintenance",
      { method: "PUT", body: JSON.stringify({ enabled, message }) }
    ),

  getPrivacyAdmin: () =>
    request<{
      slug: string;
      title: string;
      version: string;
      body: string;
      format: string;
      source: string;
    }>("/admin/settings/privacy"),

  setPrivacyAdmin: (payload: {
    title?: string;
    version?: string;
    body: string;
    format?: string;
  }) =>
    request<{
      slug: string;
      title: string;
      version: string;
      body: string;
      format: string;
      source: string;
    }>("/admin/settings/privacy", {
      method: "PUT",
      body: JSON.stringify(payload),
    }),

  getUsers: (page = 1, limit = 20, q = "") => {
    const params = new URLSearchParams({
      page: String(page),
      limit: String(limit),
    });
    if (q.trim()) params.set("q", q.trim());
    return request<{ data: UserRow[]; page: number; limit: number; total: number }>(
      `/admin/users?${params}`
    );
  },

  updateUserRole: (id: string, role: UserRole) =>
    request<UserRow>(`/admin/users/${id}/role`, {
      method: "PATCH",
      body: JSON.stringify({ role }),
    }),

  updateUserSector: (id: string, sector_name: string | null) =>
    request<UserRow>(`/admin/users/${id}/sector`, {
      method: "PATCH",
      body: JSON.stringify({ sector_name }),
    }),

  setUserActive: (id: string, is_active: boolean) =>
    request<UserRow>(`/admin/users/${id}/active`, {
      method: "PATCH",
      body: JSON.stringify({ is_active }),
    }),

  grantPremium: (user_id: string, days = 30) =>
    request<{ message: string; user: { id: string; premium_until: string } }>(
      "/premium/grant",
      { method: "POST", body: JSON.stringify({ user_id, days }) }
    ),

  revokePremium: (user_id: string) =>
    request<{ message: string; user: { id: string; premium_until: string | null } }>(
      "/premium/revoke",
      { method: "POST", body: JSON.stringify({ user_id }) }
    ),

  getPremiumSubscriptions: (page = 1, limit = 20, q = "", status = "all") => {
    const params = new URLSearchParams({
      page: String(page),
      limit: String(limit),
      status,
    });
    if (q.trim()) params.set("q", q.trim());
    return request<{
      feature_enabled: boolean;
      pricing: {
        currency: string;
        monthly_usd: number;
        yearly_usd: number;
        monthly_cdf_approx: number;
        yearly_cdf_approx: number;
      };
      plans?: {
        free: PremiumEntitlements;
        premium: PremiumEntitlements;
      };
      stats: {
        active: number;
        expired: number;
        expiring_7d: number;
        estimated_mrr_usd: number;
      };
      data: UserRow[];
      page: number;
      limit: number;
      total: number;
    }>(`/admin/premium?${params}`);
  },

  getPremiumPlans: () =>
    request<PremiumPlansPayload>("/admin/premium/plans"),

  savePremiumPlans: (body: {
    free: PremiumEntitlements;
    premium: PremiumEntitlements;
    pricing: { monthly_usd: number; yearly_usd: number; currency?: string };
  }) =>
    request<PremiumPlansPayload>("/admin/premium/plans", {
      method: "PUT",
      body: JSON.stringify(body),
    }),

  resetPremiumPlans: () =>
    request<PremiumPlansPayload>("/admin/premium/plans/reset", {
      method: "POST",
      body: JSON.stringify({}),
    }),

  getTreasury: () =>
    request<{
      balance_cdf: number;
      updated_at: string;
      pay_hub_configured: boolean;
      preferred_telecoms: string[];
      min_withdraw_cdf: number;
      ledger: Array<{
        id: string;
        direction: string;
        amount_cdf: number;
        balance_after_cdf: number;
        reason?: string | null;
        created_at: string;
      }>;
      withdrawals: Array<{
        id: string;
        amount_cdf: number;
        telecom: string;
        destination_phone: string;
        status: string;
        failure_reason?: string | null;
        created_at: string;
        completed_at?: string | null;
      }>;
    }>("/admin/treasury"),

  withdrawTreasury: (body: {
    amount_cdf: number;
    telecom: string;
    phone: string;
  }) =>
    request<{ message: string; withdrawal: unknown }>("/admin/treasury/withdraw", {
      method: "POST",
      body: JSON.stringify(body),
    }),

  getPartners: () =>
    request<{ data: PartnerRow[] }>("/admin/partners"),

  createPartner: (partner_name: string, rate_limit?: number) =>
    request<{ partner_id: string; partner_name: string; api_key: string; message: string }>(
      "/admin/partners",
      { method: "POST", body: JSON.stringify({ partner_name, rate_limit }) }
    ),

  revokePartner: (id: string) =>
    request<{ message: string }>(`/admin/partners/${id}`, { method: "DELETE" }),

  getEmergencyNumbers: () =>
    request<{ data: EmergencyRow[] }>("/admin/emergency-numbers"),

  createEmergencyNumber: (data: EmergencyInput) =>
    request<EmergencyRow>("/admin/emergency-numbers", {
      method: "POST",
      body: JSON.stringify(data),
    }),

  updateEmergencyNumber: (id: string, data: Partial<EmergencyInput>) =>
    request<EmergencyRow>(`/admin/emergency-numbers/${id}`, {
      method: "PUT",
      body: JSON.stringify(data),
    }),

  deleteEmergencyNumber: (id: string) =>
    request<{ message: string }>(`/admin/emergency-numbers/${id}`, { method: "DELETE" }),

  getIncidentTypes: () =>
    request<{ data: IncidentTypeRow[] }>("/admin/incident-types"),

  createIncidentType: (data: IncidentTypeInput) =>
    request<IncidentTypeRow>("/admin/incident-types", {
      method: "POST",
      body: JSON.stringify(data),
    }),

  updateIncidentType: (id: string, data: Partial<IncidentTypeInput>) =>
    request<IncidentTypeRow>(`/admin/incident-types/${id}`, {
      method: "PATCH",
      body: JSON.stringify(data),
    }),

  deleteIncidentType: (id: string) =>
    request<{ message: string; deleted?: boolean; deactivated?: boolean }>(
      `/admin/incident-types/${id}`,
      { method: "DELETE" }
    ),

  getIncidents: (params: Record<string, string>) => {
    const qs = new URLSearchParams(params).toString();
    return request<{ data: IncidentRow[]; page: number; limit: number; total: number }>(
      `/admin/incidents?${qs}`
    );
  },

  getTrips: (params: Record<string, string> = {}) => {
    const qs = new URLSearchParams(params).toString();
    return request<{ data: SafeTripRow[]; page: number; limit: number; total: number }>(
      `/admin/trips${qs ? `?${qs}` : ""}`
    );
  },

  getTrip: (id: string) => request<SafeTripDetail>(`/admin/trips/${id}`),

  createTrip: (data: SafeTripInput) =>
    request<SafeTripRow>("/admin/trips", {
      method: "POST",
      body: JSON.stringify(data),
    }),

  updateTrip: (id: string, data: Partial<SafeTripInput> & { eta_at?: string }) =>
    request<SafeTripRow>(`/admin/trips/${id}`, {
      method: "PATCH",
      body: JSON.stringify(data),
    }),

  deleteTrip: (id: string) =>
    request<{ message: string; id: string }>(`/admin/trips/${id}`, { method: "DELETE" }),

  getGroups: (page = 1, limit = 20, q = "") => {
    const params = new URLSearchParams({
      page: String(page),
      limit: String(limit),
    });
    if (q.trim()) params.set("q", q.trim());
    return request<{ data: GroupRow[]; page: number; limit: number; total: number }>(
      `/admin/groups?${params}`
    );
  },

  getGroup: (id: string) => request<GroupDetail>(`/admin/groups/${id}`),

  createGroup: (data: GroupInput) =>
    request<GroupRow & { admins_added?: Array<{ id: string; phone: string; pseudo: string }> }>(
      "/admin/groups",
      { method: "POST", body: JSON.stringify(data) }
    ),

  updateGroup: (id: string, data: Partial<GroupInput> & { regenerate_invite?: boolean }) =>
    request<GroupRow>(`/admin/groups/${id}`, {
      method: "PATCH",
      body: JSON.stringify(data),
    }),

  deleteGroup: (id: string) =>
    request<{ message: string; id: string }>(`/admin/groups/${id}`, { method: "DELETE" }),

  addGroupAdmin: (id: string, body: { user_id?: string; phone?: string }) =>
    request<{
      message: string;
      user: { id: string; phone: string; pseudo: string; role: string };
      created: boolean;
      promoted: boolean;
    }>(`/admin/groups/${id}/admins`, {
      method: "POST",
      body: JSON.stringify(body),
    }),

  setGroupMemberRole: (id: string, userId: string, role: "admin" | "member") =>
    request<{ id: string; user_id: string; role: string }>(
      `/admin/groups/${id}/members/${userId}`,
      { method: "PATCH", body: JSON.stringify({ role }) }
    ),

  removeGroupMember: (id: string, userId: string) =>
    request<{ message: string; user_id: string }>(
      `/admin/groups/${id}/members/${userId}`,
      { method: "DELETE" }
    ),

  getAuditLogs: (page = 1, limit = 30, q = "", action = "") => {
    const params = new URLSearchParams({
      page: String(page),
      limit: String(limit),
    });
    if (q.trim()) params.set("q", q.trim());
    if (action.trim()) params.set("action", action.trim());
    return request<{ data: AuditLogRow[]; page: number; limit: number; total: number }>(
      `/admin/audit-logs?${params}`
    );
  },

  getOpsQueue: (opts?: { mediation?: boolean }) =>
    request<{
      queue: Array<{
        id: string;
        incident_type: string;
        status: string;
        zone_name: string | null;
        age_seconds: number;
        sla_status: string;
        reporter: string;
        assignee_pseudo: string | null;
        lat: number;
        lng: number;
        mediation_requested?: boolean;
        mediation_status?: string | null;
        priority_boost?: boolean;
      }>;
      sla: {
        open_sos: number;
        sla_breach: number;
        avg_ack_seconds_24h: number | null;
      };
      busy_map: Array<{
        zone_name: string;
        active_count: number;
        avg_lat: number;
        avg_lng: number;
      }>;
      generated_at: string;
    }>(`/ops/queue${opts?.mediation ? "?mediation=1" : ""}`),

  downloadOpsReport: (format: "csv" | "pdf" = "csv", days = 7) =>
    downloadAuthenticated(
      `/ops/reports/sector?format=${format}&days=${days}`,
      `rapport-secteur-${days}j.${format}`
    ),

  listBroadcasts: () =>
    request<
      Array<{
        id: string;
        title: string;
        body: string;
        zone_name: string;
        channels: string;
        sent_count: number;
        created_at: string;
      }>
    >("/admin/broadcasts"),

  createBroadcast: (payload: {
    title: string;
    body: string;
    zone_name: string;
    channels?: string;
  }) =>
    request<{ broadcast: unknown; sent: number; targeted: number }>("/admin/broadcasts", {
      method: "POST",
      body: JSON.stringify(payload),
    }),

  updateMediation: (id: string, status: "requested" | "in_progress" | "closed") =>
    request<{ id: string; mediation_status: string }>(`/admin/incidents/${id}/mediation`, {
      method: "PATCH",
      body: JSON.stringify({ status }),
    }),
};

export interface PremiumEntitlements {
  contacts_max: number;
  trips_per_week: number | null;
  trip_eta_max_minutes: number;
  history_limit: number;
  sos_priority: boolean;
  sos_mediation: boolean;
  live_circles_max: number;
}

export interface PremiumPlansPayload {
  free: PremiumEntitlements;
  premium: PremiumEntitlements;
  pricing: {
    currency: string;
    monthly_usd: number;
    yearly_usd: number;
    monthly_cdf?: number;
    yearly_cdf?: number;
    monthly_cdf_approx: number;
    yearly_cdf_approx: number;
    usd_to_cdf_rate?: number;
  };
  defaults: {
    free: PremiumEntitlements;
    premium: PremiumEntitlements;
    pricing: PremiumPlansPayload["pricing"];
  };
  field_hints?: Record<string, string>;
}

export interface UserRow {
  id: string;
  phone: string;
  pseudo: string;
  role: UserRole;
  sector_name: string | null;
  premium_until?: string | null;
  created_at: string;
  last_seen_at: string | null;
  is_active?: boolean;
}

export interface PartnerRow {
  id: string;
  partner_name: string;
  api_key: string;
  is_active: boolean;
  rate_limit: number;
  created_at: string;
  expires_at: string | null;
}

export interface EmergencyRow {
  id: string;
  country_code: string;
  service_name: string;
  service_type: string;
  phone_number: string;
  icon: string;
  is_offline_available: boolean;
  created_at: string;
}

export interface EmergencyInput {
  country_code?: string;
  service_name: string;
  service_type: string;
  phone_number: string;
  icon?: string;
  is_offline_available?: boolean;
}

export interface IncidentTypeRow {
  id: string;
  slug: string;
  label_fr: string;
  active: boolean;
  sort_order: number;
  reportable: boolean;
  system: boolean;
  created_at: string;
  updated_at: string;
}

export interface IncidentTypeInput {
  slug?: string;
  label_fr: string;
  active?: boolean;
  sort_order?: number;
  reportable?: boolean;
}

export interface IncidentRow {
  id: string;
  incident_type: string;
  description: string | null;
  lat: number;
  lng: number;
  zone_name: string | null;
  severity: string;
  status: string;
  verified_by: number;
  is_anonymous: boolean;
  created_at: string;
  resolved_at: string | null;
  reporter: string;
  reporter_phone: string;
}

export type SafeTripStatus = "active" | "arrived" | "alerted" | "cancelled" | "expired";
export type SafeTripMode = "destination" | "patrol";

export interface SafeTripRow {
  id: string;
  user_id: string;
  status: SafeTripStatus;
  trip_mode: SafeTripMode | string;
  dest_label: string | null;
  origin_lat: number;
  origin_lng: number;
  dest_lat: number;
  dest_lng: number;
  last_lat: number | null;
  last_lng: number | null;
  eta_at: string;
  created_at: string;
  arrived_at: string | null;
  transport_mode: string | null;
  vehicle_plate: string | null;
  vehicle_note: string | null;
  notify_on_delay: boolean;
  last_ping_at: string | null;
  traveler_pseudo?: string;
  traveler_phone?: string;
}

export interface SafeTripPlace {
  id: string;
  label: string;
  lat: number;
  lng: number;
  created_at?: string;
  at?: string;
}

export interface SafeTripDetail extends SafeTripRow {
  track?: Array<{ lat: number; lng: number; recorded_at: string }>;
  places?: SafeTripPlace[];
  escort_contact_ids?: string[];
  share_token?: string | null;
  share_expires_at?: string | null;
}

export interface SafeTripInput {
  user_id?: string;
  origin_lat?: number;
  origin_lng?: number;
  dest_lat?: number;
  dest_lng?: number;
  dest_label?: string | null;
  eta_minutes?: number;
  status?: SafeTripStatus;
  trip_mode?: SafeTripMode;
  transport_mode?: string;
  vehicle_plate?: string | null;
  vehicle_note?: string | null;
  notify_on_delay?: boolean;
  last_lat?: number;
  last_lng?: number;
}

export const TRIP_STATUS_LABELS: Record<SafeTripStatus, string> = {
  active: "Actif",
  arrived: "Arrivé",
  alerted: "Alerte",
  cancelled: "Annulé",
  expired: "Expiré",
};

export const TRIP_MODE_LABELS: Record<SafeTripMode, string> = {
  destination: "Destination",
  patrol: "Patrouille",
};

export interface GroupRow {
  id: string;
  name: string;
  description: string | null;
  zone_name: string | null;
  member_count: number;
  invite_code: string;
  created_at: string;
  creator_pseudo: string;
  creator_phone: string;
  is_public?: boolean;
  created_by?: string;
  admin_count?: number;
}

export interface GroupMemberRow {
  id: string;
  user_id: string;
  role: "admin" | "member" | string;
  joined_at: string;
  pseudo: string;
  phone: string;
  user_role?: string;
}

export interface GroupDetail extends GroupRow {
  members: GroupMemberRow[];
}

export interface GroupInput {
  name: string;
  description?: string | null;
  zone_name?: string | null;
  is_public?: boolean;
  admin_user_ids?: string[];
  admin_phones?: string[];
}

export interface AuditLogRow {
  id: string;
  actor_id: string | null;
  action: string;
  entity_type: string;
  entity_id: string | null;
  metadata: Record<string, unknown> | null;
  ip: string | null;
  created_at: string;
  actor_pseudo: string | null;
  actor_phone: string | null;
}

export const ROLE_LABELS: Record<UserRole, string> = {
  citizen: "Citoyen",
  leader: "Responsable",
  agent: "Agent",
  admin: "Administrateur",
  platform_admin: "Super administrateur",
};

export const INCIDENT_STATUS_LABELS: Record<string, string> = {
  active: "Actif",
  verified: "Vérifié",
  resolved: "Résolu",
  false_alarm: "Fausse alerte",
  acknowledged: "Pris en charge",
  in_progress: "En cours",
};

export const INCIDENT_TYPE_LABELS: Record<string, string> = {
  sos: "SOS",
  agression: "Agression",
  vol: "Vol",
  accident: "Accident",
  suspect: "Présence suspecte",
  incendie: "Incendie",
  autre: "Autre",
  incident: "Incident",
};

export const SLA_STATUS_LABELS: Record<string, string> = {
  ok: "Dans les délais",
  breach: "Retard",
  warning: "Attention",
};

export const SEVERITY_LABELS: Record<string, string> = {
  alert: "Alerte",
  danger: "Danger",
  vigilance: "Vigilance",
  safe: "Sûr",
};
