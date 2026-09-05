const { Router } = require("express");
const ctrl = require("../controllers/incidentTypesController");

const router = Router();

/** Public catalog for the mobile app (report form + filters). */
router.get("/", ctrl.listPublic);

module.exports = router;
