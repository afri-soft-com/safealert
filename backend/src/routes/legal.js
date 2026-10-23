const { Router } = require("express");
const { getPublishedPrivacy } = require("../services/privacySettings");

const router = Router();

/** Public privacy policy (DB-backed, fallback to defaults). */
router.get("/privacy", async (_req, res) => {
  try {
    const doc = await getPublishedPrivacy();
    return res.json(doc);
  } catch (err) {
    console.error("GET /legal/privacy:", err.message);
    return res.status(500).json({ error: "Impossible de charger la politique de confidentialité." });
  }
});

module.exports = router;
