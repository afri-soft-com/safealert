const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { fieldDispatch } = require("../config/features");

const assignAgent = async (req, res) => {
  if (!fieldDispatch()) return res.status(503).json({ error: "Dispatch désactivé" });
  const { id } = req.params;
  const { agent_id, eta_minutes } = req.body;
  if (!agent_id) return res.status(400).json({ error: "agent_id requis" });

  try {
    const agent = await pool.query(
      `SELECT id, fcm_token, pseudo, role FROM users
       WHERE id = $1 AND role IN ('agent','leader','platform_admin')`,
      [agent_id]
    );
    if (agent.rows.length === 0) {
      return res.status(404).json({ error: "Agent non trouvé" });
    }

    const etaMins = eta_minutes ? parseInt(eta_minutes) : null;

    const result = await pool.query(
      `UPDATE incidents SET
         assigned_to = $2,
         assigned_at = NOW(),
         assignment_eta = CASE WHEN $4::int IS NOT NULL
           THEN NOW() + ($4 * INTERVAL '1 minute') ELSE NULL END,
         status = CASE WHEN status IN ('active','verified') THEN 'in_progress' ELSE status END,
         acknowledged_by = COALESCE(acknowledged_by, $3),
         acknowledged_at = COALESCE(acknowledged_at, NOW())
       WHERE id = $1 AND status IN ('active','verified','acknowledged','in_progress')
       RETURNING *`,
      [id, agent_id, req.userId, etaMins]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Incident non trouvable / non assignable" });
    }

    const incident = result.rows[0];
    const agentPseudo = agent.rows[0].pseudo;

    if (agent.rows[0].fcm_token) {
      await sendPush(agent.rows[0].fcm_token, {
        notification: {
          title: "📋 Mission SafeAlert",
          body: `Incident assigné${eta_minutes ? ` — ETA ${eta_minutes} min` : ""}`,
        },
        data: { type: "dispatch_assign", incidentId: String(id) },
      });
    }

    // Notify citizen that help is on the way
    const citizen = await pool.query(
      `SELECT fcm_token FROM users WHERE id = $1`,
      [incident.user_id]
    );
    if (citizen.rows[0]?.fcm_token) {
      await sendPush(citizen.rows[0].fcm_token, {
        notification: {
          title: "🛡️ Aide en route",
          body: etaMins
            ? `${agentPseudo} arrive dans environ ${etaMins} min`
            : `${agentPseudo} a été assigné à votre alerte`,
        },
        data: {
          type: "agent_en_route",
          incidentId: String(id),
          agentPseudo: String(agentPseudo),
          etaMinutes: etaMins != null ? String(etaMins) : "",
        },
      });
    }

    const io = req.app.get("io");
    if (io) {
      io.emit("incident_assigned", {
        id,
        agent_id,
        eta_minutes: etaMins || null,
        agent_pseudo: agentPseudo,
      });
      io.to(`user:${incident.user_id}`).emit("agent_en_route", {
        incident_id: id,
        agent_id,
        agent_pseudo: agentPseudo,
        assignment_eta: incident.assignment_eta,
        eta_minutes: etaMins || null,
      });
    }

    return res.json({
      incident,
      agent: { id: agent.rows[0].id, pseudo: agentPseudo },
    });
  } catch (err) {
    console.error("assignAgent error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const closeWithReason = async (req, res) => {
  if (!fieldDispatch()) return res.status(503).json({ error: "Dispatch désactivé" });
  const { id } = req.params;
  const { reason, status } = req.body;
  const closeStatus = status === "false_alarm" ? "false_alarm" : "resolved";
  if (!reason || String(reason).trim().length < 3) {
    return res.status(400).json({ error: "Motif de clôture requis" });
  }

  try {
    const result = await pool.query(
      `UPDATE incidents SET
         status = $2, close_reason = $3, resolved_at = NOW()
       WHERE id = $1 AND status IN ('active','verified','acknowledged','in_progress')
       RETURNING *`,
      [id, closeStatus, String(reason).trim()]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Incident non trouvé" });
    }

    const io = req.app.get("io");
    if (io) {
      io.emit("incident_closed", { id, status: closeStatus, reason });
    }

    return res.json({ incident: result.rows[0] });
  } catch (err) {
    console.error("closeWithReason error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const postChat = async (req, res) => {
  if (!fieldDispatch()) return res.status(503).json({ error: "Dispatch désactivé" });
  const { id } = req.params;
  const { body } = req.body;
  if (!body || String(body).trim().length < 1) {
    return res.status(400).json({ error: "Message requis" });
  }
  try {
    const inc = await pool.query(`SELECT id FROM incidents WHERE id = $1`, [id]);
    if (inc.rows.length === 0) return res.status(404).json({ error: "Incident non trouvé" });

    const result = await pool.query(
      `INSERT INTO incident_chat_messages (incident_id, user_id, body)
       VALUES ($1, $2, $3) RETURNING *`,
      [id, req.userId, String(body).trim().slice(0, 2000)]
    );

    const user = await pool.query(`SELECT pseudo FROM users WHERE id = $1`, [req.userId]);
    const msg = { ...result.rows[0], pseudo: user.rows[0]?.pseudo };

    const io = req.app.get("io");
    if (io) io.emit("incident_chat", { incident_id: id, message: msg });

    return res.status(201).json(msg);
  } catch (err) {
    console.error("postChat error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const getChat = async (req, res) => {
  if (!fieldDispatch()) return res.status(503).json({ error: "Dispatch désactivé" });
  try {
    const result = await pool.query(
      `SELECT m.*, u.pseudo FROM incident_chat_messages m
       JOIN users u ON u.id = m.user_id
       WHERE m.incident_id = $1
       ORDER BY m.created_at ASC LIMIT 200`,
      [req.params.id]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("getChat error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const upsertSectorGeofence = async (req, res) => {
  const { name, center_lat, center_lng, radius_m, polygon_geojson } = req.body;
  if (!name) return res.status(400).json({ error: "name requis" });

  try {
    let polygonWkt = null;
    if (polygon_geojson?.coordinates?.[0]) {
      const ring = polygon_geojson.coordinates[0]
        .map((c) => `${c[0]} ${c[1]}`)
        .join(", ");
      polygonWkt = `POLYGON((${ring}))`;
    }

    const result = await pool.query(
      `INSERT INTO leader_sectors (leader_id, name, center_lat, center_lng, radius_m, polygon)
       VALUES (
         $1, $2, $3, $4, $5,
         ${polygonWkt ? "ST_GeogFromText($6)" : "NULL"}
       )
       RETURNING id, leader_id, name, center_lat, center_lng, radius_m, created_at`,
      polygonWkt
        ? [req.userId, name, center_lat || null, center_lng || null, radius_m || 2000, polygonWkt]
        : [req.userId, name, center_lat || null, center_lng || null, radius_m || 2000]
    );
    return res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error("upsertSectorGeofence error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const listMySectors = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, name, center_lat, center_lng, radius_m, created_at
       FROM leader_sectors WHERE leader_id = $1 ORDER BY created_at DESC`,
      [req.userId]
    );
    return res.json(result.rows);
  } catch (err) {
    console.error("listMySectors error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/** Agent marks en route + optional live position for citizen */
const markEnRoute = async (req, res) => {
  if (!fieldDispatch()) return res.status(503).json({ error: "Dispatch désactivé" });
  const { id } = req.params;
  const { lat, lng, eta_minutes } = req.body || {};

  try {
    const result = await pool.query(
      `UPDATE incidents SET
         agent_en_route_at = COALESCE(agent_en_route_at, NOW()),
         agent_last_lat = COALESCE($3, agent_last_lat),
         agent_last_lng = COALESCE($4, agent_last_lng),
         assignment_eta = CASE WHEN $5::int IS NOT NULL
           THEN NOW() + ($5 * INTERVAL '1 minute') ELSE assignment_eta END,
         status = CASE WHEN status IN ('active','verified','acknowledged') THEN 'in_progress' ELSE status END
       WHERE id = $1 AND assigned_to = $2
         AND status IN ('active','verified','acknowledged','in_progress')
       RETURNING *`,
      [
        id,
        req.userId,
        lat != null ? parseFloat(lat) : null,
        lng != null ? parseFloat(lng) : null,
        eta_minutes != null ? parseInt(eta_minutes) : null,
      ]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Mission non trouvée" });
    }
    const incident = result.rows[0];
    const agent = await pool.query(`SELECT pseudo FROM users WHERE id = $1`, [req.userId]);
    const agentPseudo = agent.rows[0]?.pseudo || "Agent";

    const citizen = await pool.query(`SELECT fcm_token FROM users WHERE id = $1`, [incident.user_id]);
    if (citizen.rows[0]?.fcm_token) {
      await sendPush(citizen.rows[0].fcm_token, {
        notification: {
          title: "🛡️ Agent en route",
          body: `${agentPseudo} se dirige vers vous`,
        },
        data: { type: "agent_en_route", incidentId: String(id) },
      });
    }

    const io = req.app.get("io");
    if (io) {
      io.to(`user:${incident.user_id}`).emit("agent_en_route", {
        incident_id: id,
        agent_pseudo: agentPseudo,
        assignment_eta: incident.assignment_eta,
        agent_last_lat: incident.agent_last_lat,
        agent_last_lng: incident.agent_last_lng,
      });
    }

    return res.json({ incident, agent_pseudo: agentPseudo });
  } catch (err) {
    console.error("markEnRoute error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

/** Citizen view of assignment / ETA for own incident */
const getCitizenDispatch = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT i.id, i.status, i.assigned_to, i.assignment_eta, i.assigned_at, i.agent_en_route_at,
              i.agent_last_lat, i.agent_last_lng, i.created_at,
              u.pseudo AS agent_pseudo
       FROM incidents i
       LEFT JOIN users u ON u.id = i.assigned_to
       WHERE i.id = $1 AND i.user_id = $2`,
      [req.params.id, req.userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Alerte introuvable" });
    }
    const row = result.rows[0];
    return res.json({
      ...row,
      en_route: Boolean(row.agent_en_route_at || row.assigned_to),
      message: row.agent_pseudo
        ? `${row.agent_pseudo} ${row.agent_en_route_at ? "est en route" : "a été assigné"}`
        : "En attente d'un agent",
    });
  } catch (err) {
    console.error("getCitizenDispatch error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = {
  assignAgent,
  closeWithReason,
  postChat,
  getChat,
  upsertSectorGeofence,
  listMySectors,
  markEnRoute,
  getCitizenDispatch,
};
