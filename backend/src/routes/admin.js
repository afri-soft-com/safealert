const { Router } = require("express");
const { authenticate, requireStaff, requireSuperAdmin } = require("../middleware/auth");
const ctrl = require("../controllers/adminController");
const types = require("../controllers/incidentTypesController");

const router = Router();

router.use(authenticate, requireStaff);

router.get("/stats", ctrl.getStats);
router.get("/premium", ctrl.listPremiumSubscriptions);
router.get("/users", ctrl.listUsers);
router.patch("/users/:id/role", ctrl.updateUserRole);
router.patch("/users/:id/active", requireSuperAdmin, ctrl.setUserActive);
router.patch("/users/:id/sector", ctrl.updateUserSector);
router.get("/partners", ctrl.listPartners);
router.post("/partners", requireSuperAdmin, ctrl.createPartner);
router.delete("/partners/:id", requireSuperAdmin, ctrl.revokePartner);
router.get("/emergency-numbers", ctrl.listEmergencyNumbers);
router.post("/emergency-numbers", ctrl.createEmergencyNumber);
router.put("/emergency-numbers/:id", ctrl.updateEmergencyNumber);
router.delete("/emergency-numbers/:id", ctrl.deleteEmergencyNumber);
router.get("/incidents", ctrl.listIncidents);
router.get("/groups", ctrl.listGroups);
router.get("/audit-logs", ctrl.listAuditLogs);
router.get("/settings", ctrl.getSettings);
router.put("/settings/maintenance", requireSuperAdmin, ctrl.setMaintenanceSetting);
router.get("/incident-types", types.listStaff);
router.post("/incident-types", requireSuperAdmin, types.createType);
router.patch("/incident-types/:id", requireSuperAdmin, types.updateType);
router.delete("/incident-types/:id", requireSuperAdmin, types.deleteType);

module.exports = router;
