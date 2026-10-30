const { pool } = require("../config/database");
const { reverseGeocode, reverseGeocodePlace } = require("../services/geocode");

const clip = (value, max = 100) => {
  if (typeof value !== "string") return value;
  if (value.length <= max) return value;
  return `${value.slice(0, max - 1)}…`;
};

const resolveZoneName = async (lat, lng) => {
  try {
    return clip(await reverseGeocode(lat, lng));
  } catch (err) {
    console.warn("reverseGeocode failed:", err.message);
    return null;
  }
};

/** { zoneName, city, country } for disambiguation. */
const resolvePlace = async (lat, lng) => {
  try {
    const place = await reverseGeocodePlace(lat, lng);
    if (!place) return { zoneName: null, city: null, country: null };
    return {
      zoneName: clip(place.zoneName),
      city: clip(place.city),
      country: clip(place.country, 80),
    };
  } catch (err) {
    console.warn("reverseGeocodePlace failed:", err.message);
    return { zoneName: null, city: null, country: null };
  }
};

const insertIncidentWithZone = async (query, params, lat, lng) => {
  const zoneName = await resolveZoneName(lat, lng);
  const result = await pool.query(query, [...params, zoneName]);
  return result.rows[0];
};

module.exports = { resolveZoneName, resolvePlace, insertIncidentWithZone };
