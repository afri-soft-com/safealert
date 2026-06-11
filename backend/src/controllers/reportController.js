const PDFDocument = require("pdfkit");
const { pool } = require("../config/database");

const generateReport = async (req, res) => {
  const { start_date, end_date, zone } = req.query;
  const days = parseInt(req.query.days) || 7;

  try {
    const dateFilter = start_date && end_date
      ? [`created_at >= $1 AND created_at <= $2`, start_date, end_date]
      : [`created_at > NOW() - INTERVAL '${days} days'`, null, null];

    const params = [];
    let whereClause = `WHERE i.created_at > NOW() - INTERVAL '${days} days'`;
    if (zone) {
      params.push(zone);
      whereClause += ` AND i.zone_name = $${params.length}`;
    }

    const incidents = await pool.query(`
      SELECT i.id, i.incident_type, i.description, i.lat, i.lng,
             i.severity, i.status, i.verified_by, i.zone_name, i.created_at,
             COALESCE(u.pseudo, 'Anonyme') as reporter
      FROM incidents i
      LEFT JOIN users u ON i.user_id = u.id
      ${whereClause}
      ORDER BY i.created_at DESC
    `, params);

    const stats = await pool.query(`
      SELECT
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE status = 'active') as active,
        COUNT(*) FILTER (WHERE status = 'verified') as verified,
        COUNT(*) FILTER (WHERE status = 'resolved') as resolved,
        COUNT(*) FILTER (WHERE severity = 'alert') as alerts,
        COUNT(*) FILTER (WHERE severity = 'vigilance') as vigilance,
        COUNT(DISTINCT incident_type) as type_count,
        COUNT(DISTINCT user_id) as reporters
      FROM incidents ${whereClause}
    `, params);
    const s = stats.rows[0];

    const doc = new PDFDocument({ margin: 40, size: "A4" });

    res.setHeader("Content-Type", "application/pdf");
    res.setHeader("Content-Disposition", `attachment; filename="rapport-incidents-${new Date().toISOString().slice(0, 10)}.pdf"`);
    doc.pipe(res);

    const blue = "#0D1B2A";
    const red = "#CC1C1C";
    const gray = "#4A4A6A";

    doc.fontSize(22).font("Helvetica-Bold").fillColor(red).text("SafeAlert", { continued: true });
    doc.fontSize(22).fillColor(blue).text(" — Rapport d'Incidents");

    doc.fontSize(9).fillColor(gray)
      .text(`Généré le ${new Date().toLocaleDateString("fr-FR")}`, { align: "right" })
      .moveDown(0.5);

    doc.fontSize(10).fillColor(blue).text(`Période : ${start_date || `7 derniers jours`}${end_date ? ` → ${end_date}` : ''}${zone ? ` · Zone : ${zone}` : ''}`);
    doc.moveDown(1);

    doc.fontSize(14).fillColor(blue).text("Résumé").moveDown(0.3);
    doc.fontSize(10).fillColor(gray);
    doc.text(`Total incidents : ${s.total}`);
    doc.text(`Actifs : ${s.active}  ·  Vérifiés : ${s.verified}  ·  Résolus : ${s.resolved}`);
    doc.text(`Alertes SOS : ${s.alerts}  ·  Vigilances : ${s.vigilance}`);
    doc.text(`Types distincts : ${s.type_count}  ·  Signalants : ${s.reporters}`);
    doc.moveDown(1);

    doc.fontSize(14).fillColor(blue).text("Détail des incidents").moveDown(0.3);

    if (incidents.rows.length === 0) {
      doc.fontSize(10).fillColor(gray).text("Aucun incident dans la période sélectionnée.");
    } else {
      const tableTop = doc.y;
      const colWidths = [120, 70, 80, 60, 60];
      const headers = ["Type", "Date", "Statut", "Zone", "Signalant"];

      doc.fontSize(8).font("Helvetica-Bold").fillColor(blue);
      let x = 40;
      for (let i = 0; i < headers.length; i++) {
        doc.text(headers[i], x, tableTop, { width: colWidths[i], align: "left" });
        x += colWidths[i];
      }

      doc.moveDown(0.3);
      doc.fontSize(8).font("Helvetica").fillColor(gray);

      for (const row of incidents.rows) {
        if (doc.y > 720) {
          doc.addPage();
          doc.fontSize(8).font("Helvetica").fillColor(gray);
        }
        const y = doc.y;
        x = 40;
        const cols = [
          row.incident_type,
          new Date(row.created_at).toLocaleDateString("fr-FR"),
          row.status,
          row.zone_name || "-",
          row.reporter,
        ];
        for (let i = 0; i < cols.length; i++) {
          doc.text(cols[i], x, y, { width: colWidths[i], align: "left" });
          x += colWidths[i];
        }
        doc.moveDown(0.4);
      }
    }

    doc.moveDown(1);
    doc.fontSize(8).fillColor(gray)
      .text(`SafeAlert v1.0 — Rapport généré automatiquement le ${new Date().toISOString()}`, { align: "center" });

    doc.end();
  } catch (err) {
    console.error("generateReport error:", err);
    res.status(500).json({ error: "Erreur lors de la génération du rapport" });
  }
};

module.exports = { generateReport };