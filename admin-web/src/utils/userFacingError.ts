import { ApiError } from "../api/client";

const TECHNICAL =
  /exception|stack\s*trace|sql|postgres|redis|econnrefused|internal server|typeerror|null check|render\.com|errno/i;

export function messageForStatus(status: number): string {
  switch (status) {
    case 400:
      return "Demande invalide. Vérifiez les informations saisies.";
    case 401:
      return "Session expirée. Veuillez vous reconnecter.";
    case 403:
      return "Accès non autorisé pour votre profil.";
    case 404:
      return "Élément introuvable.";
    case 409:
      return "Conflit : cette action n'est plus possible.";
    case 422:
      return "Informations incomplètes ou incorrectes.";
    case 429:
      return "Trop de tentatives. Réessayez dans quelques instants.";
    case 500:
    case 502:
    case 503:
    case 504:
      return "Service temporairement indisponible. Réessayez plus tard.";
    default:
      return status >= 500
        ? "Service temporairement indisponible. Réessayez plus tard."
        : "Une erreur est survenue. Réessayez.";
  }
}

const KNOWN: Record<string, string> = {
  "invalid phone": "Numéro de téléphone invalide.",
  "invalid code": "Code incorrect. Vérifiez le SMS et réessayez.",
  "code expired": "Code expiré. Demandez un nouveau code.",
  unauthorized: "Session expirée. Veuillez vous reconnecter.",
  forbidden: "Accès non autorisé pour votre profil.",
  "not found": "Élément introuvable.",
  "too many requests": "Trop de tentatives. Réessayez dans quelques instants.",
  "rate limit": "Trop de demandes. Réessayez plus tard.",
  "invalid api key": "Clé API invalide ou expirée.",
  "invalid or inactive api key": "Clé API invalide ou expirée.",
  "partner not found": "Partenaire introuvable.",
  "erreur serveur": "Une erreur est survenue. Réessayez.",
  feature_premium: "Cette fonction n'est pas encore disponible.",
  feature_: "Cette fonction n'est pas encore disponible.",
  "internal server": "Une erreur est survenue. Réessayez.",
};

export function looksTechnical(message: string): boolean {
  const m = message.trim();
  if (!m) return true;
  if (TECHNICAL.test(m)) return true;
  if (/FEATURE_[A-Z0-9_]+/.test(m)) return true;
  if (/^erreur\s+\d{3}$/i.test(m)) return true;
  return false;
}

export function userFacingError(err: unknown, fallback = "Une erreur est survenue. Réessayez."): string {
  if (err instanceof ApiError) {
    const lower = err.message.toLowerCase();
    for (const [key, value] of Object.entries(KNOWN)) {
      if (lower.includes(key)) return value;
    }
    if (!looksTechnical(err.message)) return err.message;
    return messageForStatus(err.status);
  }
  if (err instanceof Error) {
    const lower = err.message.toLowerCase();
    for (const [key, value] of Object.entries(KNOWN)) {
      if (lower.includes(key)) return value;
    }
    if (!looksTechnical(err.message) && err.message.length < 160) return err.message;
  }
  return fallback;
}

export const INCIDENT_TYPE_LABELS: Record<string, string> = {
  sos: "SOS",
  vol: "Vol",
  agression: "Agression",
  suspect: "Présence suspecte",
  incendie: "Incendie",
  incident: "Incident",
};

export const SLA_LABELS: Record<string, string> = {
  ok: "Dans les délais",
  warning: "Attention",
  breach: "Dépassée",
  breached: "Dépassée",
};
