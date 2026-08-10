const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { sectorGeofence } = require("../config/features");

/**
 * Notify leaders whose sector geofence / radius contains the SOS point,
 * or whose sector_name matches the incident zone_name.
 */
const notifyLeadersForSOS = async (incident) => {
  if (!sectorGeofence()) return { leadersNotified: 0 };

  const { id, lat, lng, zone_name, incident_type } = incident;
  let leadersNotified = 0;

  try {
    const geoLeaders = await pool.query(
      `SELECT DISTINCT u.id, u.fcm_token, ls.name as sector
       FROM leader_sectors ls
       JOIN users u ON u.id = ls.leader_id
       WHERE u.role IN ('leader', 'agent', 'platform_admin')
         AND (
           (ls.polygon IS NOT NULL AND ST_Covers(
             ls.polygon,
             ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography
           ))
           OR (
             ls.center_lat IS NOT NULL AND ls.center_lng IS NOT NULL
             AND ST_DWithin(
               ST_SetSRID(ST_MakePoint(ls.center_lng, ls.center_lat), 4326)::geography,
               ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
               COALESCE(ls.radius_m, 2000)
             )
           )
         )`,
      [lng, lat]
    );

    const nameLeaders = zone_name
      ? await pool.query(
          `SELECT id, fcm_token, sector_name as sector FROM users
           WHERE role IN ('leader', 'agent')
             AND sector_name IS NOT NULL
             AND $1 ILIKE '%' || sector_name || '%'`,
          [zone_name]
        )
      : { rows: [] };

    const seen = new Set();
    const all = [...geoLeaders.rows, ...nameLeaders.rows];
    for (const leader of all) {
      if (seen.has(leader.id)) continue;
      seen.add(leader.id);
      if (leader.fcm_token) {
        await sendPush(leader.fcm_token, {
          notification: {
            title: "🚨 SOS dans votre secteur",
            body: `${incident_type || "sos"} — ${zone_name || "zone inconnue"}`,
          },
          data: {
            type: "sector_sos",
            incidentId: String(id),
            lat: String(lat),
            lng: String(lng),
          },
        });
        leadersNotified += 1;
      }
    }
  } catch (err) {
    console.error("notifyLeadersForSOS error:", err.message);
  }

  return { leadersNotified };
};

module.exports = { notifyLeadersForSOS };
