export const API_BASE =
  import.meta.env.VITE_API_BASE_URL?.replace(/\/$/, "") || "/api";

const TOKEN_KEY = "safealert_admin_token";
const USER_KEY = "safealert_admin_user";

export type UserRole = "citizen" | "leader" | "agent" | "platform_admin";

export interface AuthUser {
  id: string;
  phone: string;
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
    request<{ message: string; devCode?: string }>("/auth/request-code", {
      method: "POST",
      body: JSON.stringify({ phone }),
    }),

  verifyCode: (phone: string, code: string, pseudo?: string) =>
    request<{ token: string; user: AuthUser }>("/auth/verify-code", {
      method: "POST",
      body: JSON.stringify({
        phone,
        code,
        ...(pseudo?.trim() ? { pseudo: pseudo.trim() } : {}),
      }),
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

  getIncidents: (params: Record<string, string>) => {
    const qs = new URLSearchParams(params).toString();
    return request<{ data: IncidentRow[]; page: number; limit: number; total: number }>(
      `/admin/incidents?${qs}`
    );
  },

  getGroups: (page = 1, limit = 20) =>
    request<{ data: GroupRow[]; page: number; limit: number; total: number }>(
      `/admin/groups?page=${page}&limit=${limit}`
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

  getOpsQueue: () =>
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
    }>("/ops/queue"),

  downloadOpsReport: (format: "csv" | "pdf" = "csv", days = 7) =>
    downloadAuthenticated(
      `/ops/reports/sector?format=${format}&days=${days}`,
      `rapport-secteur-${days}j.${format}`
    ),
};

export interface UserRow {
  id: string;
  phone: string;
  pseudo: string;
  role: UserRole;
  sector_name: string | null;
  created_at: string;
  last_seen_at: string | null;
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
  platform_admin: "Admin plateforme",
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
  suspect: "Présence suspecte",
  incendie: "Incendie",
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
