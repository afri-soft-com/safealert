require("dotenv").config();
const { pool } = require("./database");

const seed = async () => {
  const client = await pool.connect();
  try {
    await client.query("DELETE FROM emergency_numbers");

    const numbers = [
      { country_code: "CD", service_name: "Police nationale", service_type: "police", phone_number: "112", icon: "🚔" },
      { country_code: "CD", service_name: "Hôpital général", service_type: "medical", phone_number: "15", icon: "🏥" },
      { country_code: "CD", service_name: "Pompiers", service_type: "fire", phone_number: "118", icon: "🚒" },
      { country_code: "CD", service_name: "Gendarmerie locale", service_type: "police", phone_number: "+243 81 555 1000", icon: "👮" },
      { country_code: "CD", service_name: "Croix-Rouge RDC", service_type: "medical", phone_number: "+243 81 700 2000", icon: "🏛" },
    ];

    for (const n of numbers) {
      await client.query(
        `INSERT INTO emergency_numbers (country_code, service_name, service_type, phone_number, icon)
         VALUES ($1, $2, $3, $4, $5)`,
        [n.country_code, n.service_name, n.service_type, n.phone_number, n.icon]
      );
    }

    console.log("Seed completed successfully");
  } catch (err) {
    console.error("Seed failed:", err);
    throw err;
  } finally {
    client.release();
    await pool.end();
  }
};

seed();
