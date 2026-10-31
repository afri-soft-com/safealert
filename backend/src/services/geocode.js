/**
 * Reverse geocoding via Nominatim (OpenStreetMap).
 * Respects Nominatim usage policy: User-Agent, max 1 req/s, caching.
 * @see https://nominatim.org/release-docs/latest/api/Reverse/
 */

const NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse";
const USER_AGENT =
  process.env.NOMINATIM_USER_AGENT || "SafeAlert/1.0 (citizen-safety-app; contact@safealert.local)";
const MIN_INTERVAL_MS = 1100;

const cache = new Map();
let lastRequestAt = 0;

const cacheKey = (lat, lng) => `${lat.toFixed(4)},${lng.toFixed(4)}`;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const MEGA_CITIES = new Set([
  "kinshasa",
  "lubumbashi",
  "mbuji-mayi",
  "mbujimayi",
  "goma",
  "bukavu",
  "brazzaville",
  "pointe-noire",
]);

const norm = (s) =>
  String(s || "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();

const cleanDistrict = (raw) => {
  if (!raw) return null;
  return String(raw)
    .replace(/^commune\s+(de\s+)?/i, "")
    .trim();
};

const isMega = (name) => {
  const n = norm(name);
  if (!n) return false;
  if (MEGA_CITIES.has(n)) return true;
  return n.includes("ville de kinshasa");
};

/** Quartier / neighbourhood — prefer fine grain over province. */
const pickZoneName = (address) => {
  if (!address || typeof address !== "object") return null;
  const mega = isMega(address.city) || isMega(address.state);
  if (mega) {
    return (
      address.neighbourhood ||
      address.quarter ||
      address.residential ||
      (address.suburb &&
      norm(address.suburb) !== norm(address.city_district || address.borough)
        ? address.suburb
        : null) ||
      cleanDistrict(address.city_district) ||
      address.suburb ||
      null
    );
  }
  return (
    address.neighbourhood ||
    address.quarter ||
    address.suburb ||
    address.residential ||
    cleanDistrict(address.city_district) ||
    address.city ||
    address.town ||
    address.village ||
    address.municipality ||
    address.county ||
    null
  );
};

/** Commune / city — for Kinshasa, suburb/city_district is the commune. */
const pickCity = (address) => {
  if (!address || typeof address !== "object") return null;
  const mega = isMega(address.city) || isMega(address.state);
  if (mega) {
    return (
      cleanDistrict(address.city_district) ||
      address.borough ||
      address.municipality ||
      address.suburb ||
      address.city ||
      address.town ||
      null
    );
  }
  return (
    address.municipality ||
    cleanDistrict(address.city_district) ||
    address.borough ||
    address.city ||
    address.town ||
    address.village ||
    address.county ||
    address.state ||
    null
  );
};

const fetchNominatim = async (latNum, lngNum) => {
  const key = cacheKey(latNum, lngNum);
  if (cache.has(key)) return cache.get(key);

  const elapsed = Date.now() - lastRequestAt;
  if (elapsed < MIN_INTERVAL_MS) {
    await sleep(MIN_INTERVAL_MS - elapsed);
  }

  const url = `${NOMINATIM_URL}?lat=${latNum}&lon=${lngNum}&format=json&addressdetails=1&zoom=18`;
  lastRequestAt = Date.now();

  const res = await fetch(url, {
    headers: { "User-Agent": USER_AGENT, Accept: "application/json" },
  });

  if (!res.ok) {
    throw new Error(`Nominatim HTTP ${res.status}`);
  }

  const data = await res.json();
  const place = {
    zoneName: pickZoneName(data.address),
    city: pickCity(data.address),
    country: data.address?.country || null,
  };
  cache.set(key, place);
  return place;
};

/** Full place (quartier + city). */
const reverseGeocodePlace = async (lat, lng) => {
  const latNum = parseFloat(lat);
  const lngNum = parseFloat(lng);
  if (Number.isNaN(latNum) || Number.isNaN(lngNum)) return null;
  return fetchNominatim(latNum, lngNum);
};

/** Backward-compatible: returns zone name string only. */
const reverseGeocode = async (lat, lng) => {
  const place = await reverseGeocodePlace(lat, lng);
  return place?.zoneName || null;
};

/** Clear in-memory cache (tests). */
const clearGeocodeCache = () => cache.clear();

module.exports = {
  reverseGeocode,
  reverseGeocodePlace,
  pickZoneName,
  pickCity,
  clearGeocodeCache,
};
