const { Router } = require("express");
const ctrl = require("../controllers/webhooksController");

const router = Router();

router.post("/afrisoft-payments", ctrl.afrisoftPaymentsWebhook);

module.exports = router;
