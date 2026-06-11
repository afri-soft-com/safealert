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

const pickZoneName = (address) => {
  if (!address || typeof address !== "object") return null;
  return (
    address.suburb ||
    address.neighbourhood ||
    address.city_district ||
    address.quarter ||
    address.city ||
    address.town ||
    address.village ||
    address.municipality ||
    address.county ||
    null
  );
};

const reverseGeocode = async (lat, lng) => {
  const latNum = parseFloat(lat);
  const lngNum = parseFloat(lng);
  if (Number.isNaN(latNum) || Number.isNaN(lngNum)) return null;

  const key = cacheKey(latNum, lngNum);
  if (cache.has(key)) return cache.get(key);

  const elapsed = Date.now() - lastRequestAt;
  if (elapsed < MIN_INTERVAL_MS) {
    await sleep(MIN_INTERVAL_MS - elapsed);
  }

  const url = `${NOMINATIM_URL}?lat=${latNum}&lon=${lngNum}&format=json&addressdetails=1&zoom=14`;
  lastRequestAt = Date.now();

  const res = await fetch(url, {
    headers: { "User-Agent": USER_AGENT, Accept: "application/json" },
  });

  if (!res.ok) {
    throw new Error(`Nominatim HTTP ${res.status}`);
  }

  const data = await res.json();
  const zoneName = pickZoneName(data.address);
  if (zoneName) {
    cache.set(key, zoneName);
  }
  return zoneName;
};

/** Clear in-memory cache (tests). */
const clearGeocodeCache = () => cache.clear();

module.exports = { reverseGeocode, pickZoneName, clearGeocodeCache };
