const EARTH_KM = 6371;

const toRad = (deg) => (deg * Math.PI) / 180;

const haversineKm = (lat1, lng1, lat2, lng2) => {
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return EARTH_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

/** Vitesses moyennes urbaines RDC (km/h). */
const TRANSPORT_SPEEDS_KMH = {
  walk: 5,
  moto: 28,
  car: 22,
};

const normalizeTransportMode = (raw) => {
  const m = String(raw || "").toLowerCase().trim();
  if (m === "walk" || m === "pied" || m === "foot") return "walk";
  if (m === "car" || m === "voiture" || m === "vehicle" || m === "vehicule") return "car";
  return "moto";
};

const estimateEtaMinutes = (lat1, lng1, lat2, lng2, mode) => {
  const speed = TRANSPORT_SPEEDS_KMH[normalizeTransportMode(mode)] || TRANSPORT_SPEEDS_KMH.moto;
  const km = haversineKm(Number(lat1), Number(lng1), Number(lat2), Number(lng2));
  if (!Number.isFinite(km) || km <= 0) return 5;
  return Math.max(5, Math.ceil((km / speed) * 60));
};

module.exports = {
  haversineKm,
  TRANSPORT_SPEEDS_KMH,
  normalizeTransportMode,
  estimateEtaMinutes,
};
