const { Router } = require("express");
const { authenticate, requireRole } = require("../middleware/auth");
const ctrl = require("../controllers/adminController");

const router = Router();

router.use(authenticate, requireRole("platform_admin"));

router.get("/stats", ctrl.getStats);
router.get("/users", ctrl.listUsers);
router.patch("/users/:id/role", ctrl.updateUserRole);
router.patch("/users/:id/sector", ctrl.updateUserSector);
router.get("/partners", ctrl.listPartners);
router.post("/partners", ctrl.createPartner);
router.delete("/partners/:id", ctrl.revokePartner);
router.get("/emergency-numbers", ctrl.listEmergencyNumbers);
router.post("/emergency-numbers", ctrl.createEmergencyNumber);
router.put("/emergency-numbers/:id", ctrl.updateEmergencyNumber);
router.delete("/emergency-numbers/:id", ctrl.deleteEmergencyNumber);
router.get("/incidents", ctrl.listIncidents);
router.get("/groups", ctrl.listGroups);
router.get("/audit-logs", ctrl.listAuditLogs);

module.exports = router;
