const { Router } = require("express");
const { authenticate, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/adminController");

const router = Router();

router.use(authenticate, requireRole("platform_admin"));

router.get("/users", ctrl.listUsers);
router.patch("/users/:id/role", ctrl.updateUserRole);
router.patch("/users/:id/sector", ctrl.updateUserSector);
router.get("/partners", ctrl.listPartners);
router.post("/partners", ctrl.createPartner);
router.delete("/partners/:id", ctrl.revokePartner);

module.exports = router;
