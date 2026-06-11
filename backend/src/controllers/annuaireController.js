const { pool } = require("../config/database");

const getNumbers = async (req, res) => {
  const { country } = req.query;
  try {
    let query = "SELECT * FROM emergency_numbers";
    const params = [];
    if (country) {
      query += " WHERE country_code = $1";
      params.push(country.toUpperCase());
    }
    query += " ORDER BY service_type, service_name";
    const result = await pool.query(query, params);
    return res.json(result.rows);
  } catch (err) {
    console.error("getNumbers error:", err);
    return res.status(500).json({ error: "Erreur serveur" });
  }
};

module.exports = { getNumbers };
