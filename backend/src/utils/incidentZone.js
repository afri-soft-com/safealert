const { pool } = require("../config/database");
const { reverseGeocode } = require("../services/geocode");

const resolveZoneName = async (lat, lng) => {
  try {
    return await reverseGeocode(lat, lng);
  } catch (err) {
    console.warn("reverseGeocode failed:", err.message);
    return null;
  }
};

const insertIncidentWithZone = async (query, params, lat, lng) => {
  const zoneName = await resolveZoneName(lat, lng);
  const result = await pool.query(query, [...params, zoneName]);
  return result.rows[0];
};

module.exports = { resolveZoneName, insertIncidentWithZone };
