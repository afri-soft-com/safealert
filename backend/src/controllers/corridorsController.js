const { pool } = require("../config/database");
const { corridors } = require("../config/features");

const assertEnabled = (res) => {
  if (!corridors()) {
    res.status(503).json({ error: "Corridors désactivés" });
    return false;
  }
  return true;
};

/** Nearby landmarks / corridors */
const listNearby = async (req, res) => {
  if (!assertEnabled(res)) return;
  const lat = parseFloat(req.query.lat);
  const lng = parseFloat(req.query.lng);
  const radiusM = Math.min(parseInt(req.query.radius_m) || 3000, 15000);

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return res.status(400).json({ error: "lat et lng requis" });
  }

  try {
    const result = await pool.query(
      `SELECT id, name, kind, lat, lng, zone_name, description,
              ROUND(ST_Distance(
                location,
                ST_SetSRID(ST_MakePoint($2,$1),4326)::geography
              )::numeric, 0) AS distance_m
       FROM landmarks
       WHERE ST_DWithin(
         location,
         ST_SetSRID(ST_MakePoint($2,$1),4326)::geography,
         $3
       )
       ORDER BY distance_m ASC
       LIMIT 30`,
      [lat, lng, radiusM]
    );
    return res.json({ landmarks: result.rows });
  } catch (err) {
    console.error("listNearby landmarks error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

/**
 * Suggest "busier" vs quieter approach toward destination based on
 * recent incident density near candidate landmarks along the way (MVP).
 */
const suggestRoutes = async (req, res) => {
  if (!assertEnabled(res)) return;
  const originLat = parseFloat(req.query.origin_lat ?? req.body?.origin_lat);
  const originLng = parseFloat(req.query.origin_lng ?? req.body?.origin_lng);
  const destLat = parseFloat(req.query.dest_lat ?? req.body?.dest_lat);
  const destLng = parseFloat(req.query.dest_lng ?? req.body?.dest_lng);

  if (![originLat, originLng, destLat, destLng].every(Number.isFinite)) {
    return res.status(400).json({ error: "Origine et destination requises" });
  }

  try {
    // Landmarks roughly between origin and dest (bbox + near midpoint)
    const midLat = (originLat + destLat) / 2;
    const midLng = (originLng + destLng) / 2;

    const landmarks = await pool.query(
      `SELECT l.id, l.name, l.kind, l.lat, l.lng, l.zone_name,
              COALESCE((
                SELECT COUNT(*)::int FROM incidents i
                WHERE i.created_at > NOW() - INTERVAL '7 days'
                  AND ST_DWithin(
                    i.location,
                    ST_SetSRID(ST_MakePoint(l.lng, l.lat),4326)::geography,
                    800
                  )
              ), 0) AS recent_incidents
       FROM landmarks l
       WHERE ST_DWithin(
         l.location,
         ST_SetSRID(ST_MakePoint($1,$2),4326)::geography,
         8000
       )
       ORDER BY recent_incidents ASC, name ASC
       LIMIT 12`,
      [midLng, midLat]
    );

    const sorted = [...landmarks.rows].sort(
      (a, b) => a.recent_incidents - b.recent_incidents
    );
    const quieter = sorted.slice(0, 3);
    const busier = [...sorted].sort((a, b) => b.recent_incidents - a.recent_incidents).slice(0, 3);

    return res.json({
      midpoint: { lat: midLat, lng: midLng },
      suggestion:
        quieter[0]
          ? `Passez plutôt près de « ${quieter[0].name} » — moins d'incidents récents.`
          : "Pas assez de données pour suggérer un itinéraire.",
      quieter_via: quieter,
      busier_via: busier,
      note: "Indication indicative basée sur les signalements des 7 derniers jours.",
    });
  } catch (err) {
    console.error("suggestRoutes error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { listNearby, suggestRoutes };
