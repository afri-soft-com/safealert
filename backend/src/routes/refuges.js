const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/refugeController");

const router = Router();

// Public places (hospitals, pharmacies…): readable without an account.
router.get("/", ctrl.listRefuges);
router.post("/", authenticate, ctrl.createRefuge);
router.delete("/:id", authenticate, ctrl.deleteRefuge);

module.exports = router;
