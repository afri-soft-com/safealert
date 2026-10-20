const { pool } = require("../config/database");
const { opsDashboard, autoReports } = require("../config/features");
const PDFDocument = require("pdfkit");

const getOpsQueue = async (req, res) => {
  if (!opsDashboard()) return res.status(503).json({ error: "Ops dashboard désactivé" });
  try {
    const mediationOnly = req.query.mediation === "1" || req.query.mediation === "true";
    const queue = await pool.query(`
      SELECT i.id, i.incident_type, i.severity, i.status, i.lat, i.lng, i.zone_name,
             i.created_at, i.acknowledged_at, i.assigned_to, i.assignment_eta,
             COALESCE(i.priority_boost, false) as priority_boost,
             COALESCE(i.mediation_requested, false) as mediation_requested,
             i.mediation_status,
             COALESCE(u.pseudo, 'Anonyme') as reporter,
             a.pseudo as assignee_pseudo,
             EXTRACT(EPOCH FROM (NOW() - i.created_at))::int as age_seconds,
             CASE
               WHEN i.status = 'active' AND i.created_at < NOW() - INTERVAL '5 minutes' THEN 'breach'
               WHEN i.status IN ('acknowledged','in_progress') AND i.acknowledged_at < NOW() - INTERVAL '30 minutes' THEN 'warning'
               ELSE 'ok'
             END as sla_status
      FROM incidents i
      LEFT JOIN users u ON i.user_id = u.id
      LEFT JOIN users a ON i.assigned_to = a.id
      WHERE i.status IN ('active','verified','acknowledged','in_progress')
        AND i.severity IN ('alert','danger')
        AND ($1::boolean = false OR COALESCE(i.mediation_requested, false) = true)
      ORDER BY
        CASE WHEN COALESCE(i.mediation_requested, false) THEN 0 ELSE 1 END,
        CASE WHEN COALESCE(i.priority_boost, false) THEN 0 ELSE 1 END,
        CASE i.status WHEN 'active' THEN 0 WHEN 'verified' THEN 1 ELSE 2 END,
        i.created_at ASC
      LIMIT 100
    `, [mediationOnly]);

    const sla = await pool.query(`
      SELECT
        COUNT(*) FILTER (WHERE status = 'active')::int as open_sos,
        COUNT(*) FILTER (
          WHERE status = 'active' AND created_at < NOW() - INTERVAL '5 minutes'
        )::int as sla_breach,
        ROUND(AVG(
          EXTRACT(EPOCH FROM (COALESCE(acknowledged_at, NOW()) - created_at))
        ) FILTER (WHERE severity = 'alert' AND created_at > NOW() - INTERVAL '24 hours'))::int
          as avg_ack_seconds_24h
      FROM incidents
      WHERE created_at > NOW() - INTERVAL '24 hours' OR status IN ('active','acknowledged','in_progress')
    `);

    const busyMap = await pool.query(`
      SELECT zone_name, COUNT(*)::int as active_count,
             ROUND(AVG(lat)::numeric, 4) as avg_lat,
             ROUND(AVG(lng)::numeric, 4) as avg_lng
      FROM incidents
      WHERE status IN ('active','verified','acknowledged','in_progress')
        AND zone_name IS NOT NULL
      GROUP BY zone_name
      ORDER BY active_count DESC
      LIMIT 30
    `);

    return res.json({
      queue: queue.rows,
      sla: sla.rows[0],
      busy_map: busyMap.rows,
      generated_at: new Date().toISOString(),
    });
  } catch (err) {
    console.error("getOpsQueue error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

const exportSectorReport = async (req, res) => {
  if (!autoReports()) return res.status(503).json({ error: "Rapports auto désactivés" });
  const format = (req.query.format || "csv").toLowerCase();
  const sector = req.query.sector || req.userSector || null;
  const days = Math.min(parseInt(req.query.days) || 7, 90);

  try {
    const params = [days];
    let where = `WHERE i.created_at > NOW() - ($1 * INTERVAL '1 day')`;
    if (sector) {
      params.push(`%${sector}%`);
      where += ` AND i.zone_name ILIKE $2`;
    }

    const incidents = await pool.query(
      `SELECT i.id, i.incident_type, i.status, i.severity, i.zone_name,
              i.lat, i.lng, i.created_at, i.resolved_at, i.close_reason,
              COALESCE(u.pseudo,'Anonyme') as reporter
       FROM incidents i
       LEFT JOIN users u ON i.user_id = u.id
       ${where}
       ORDER BY i.created_at DESC`,
      params
    );

    if (format === "csv") {
      res.setHeader("Content-Type", "text/csv; charset=utf-8");
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="safealert-secteur-${new Date().toISOString().slice(0, 10)}.csv"`
      );
      const header = "id,type,status,severity,zone,lat,lng,created_at,resolved_at,reporter,close_reason\n";
      const rows = incidents.rows.map((r) =>
        [
          r.id, r.incident_type, r.status, r.severity,
          JSON.stringify(r.zone_name || ""),
          r.lat, r.lng, r.created_at?.toISOString?.() || r.created_at,
          r.resolved_at?.toISOString?.() || r.resolved_at || "",
          JSON.stringify(r.reporter || ""),
          JSON.stringify(r.close_reason || ""),
        ].join(",")
      );
      return res.send(header + rows.join("\n"));
    }

    // PDF entreprise
    const byType = {};
    const byStatus = {};
    for (const r of incidents.rows) {
      byType[r.incident_type] = (byType[r.incident_type] || 0) + 1;
      byStatus[r.status] = (byStatus[r.status] || 0) + 1;
    }
    const doc = new PDFDocument({ margin: 48, size: "A4" });
    res.setHeader("Content-Type", "application/pdf");
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="safealert-rapport-${new Date().toISOString().slice(0, 10)}.pdf"`
    );
    doc.pipe(res);
    doc.fontSize(22).fillColor("#0B6E6E").text("SafeAlert", { continued: false });
    doc.fontSize(14).fillColor("#CC1C1C").text("Rapport incidents — usage entreprise");
    doc.moveDown(0.5);
    doc.fontSize(10).fillColor("#4A4A6A")
      .text(`Période : ${days} jours`)
      .text(`Secteur / commune : ${sector || "tous"}`)
      .text(`Généré le : ${new Date().toLocaleString("fr-FR")}`)
      .text(`Total incidents : ${incidents.rows.length}`)
      .moveDown();
    doc.fontSize(12).fillColor("#0D1B2A").text("Synthèse");
    doc.fontSize(9).fillColor("#4A4A6A");
    Object.entries(byType).forEach(([k, v]) => doc.text(`  Type ${k} : ${v}`));
    Object.entries(byStatus).forEach(([k, v]) => doc.text(`  Statut ${k} : ${v}`));
    doc.moveDown();
    doc.fontSize(12).fillColor("#0D1B2A").text("Détail (max 120)");
    doc.moveDown(0.3);
    for (const r of incidents.rows.slice(0, 120)) {
      if (doc.y > 720) doc.addPage();
      const when = r.created_at?.toISOString?.()?.slice(0, 16) || r.created_at || "";
      doc.fontSize(9).fillColor("#0D1B2A")
        .text(`${when} · ${r.incident_type} · ${r.status} · ${r.zone_name || "—"} · ${r.reporter}`);
      if (r.close_reason) {
        doc.fontSize(8).fillColor("#666").text(`   Clôture : ${r.close_reason}`);
      }
    }
    doc.moveDown();
    doc.fontSize(8).fillColor("#888").text("Document confidentiel — SafeAlert. Ne pas redistribuer hors cadre partenaire.");
    doc.end();
  } catch (err) {
    console.error("exportSectorReport error:", err);
    return res.status(500).json({ error: "Une erreur est survenue. Réessayez." });
  }
};

module.exports = { getOpsQueue, exportSectorReport };
