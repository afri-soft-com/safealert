const { Router } = require("express");
const { authenticate } = require("../middleware/auth");
const ctrl = require("../controllers/contactsController");

const router = Router();

router.get("/", authenticate, ctrl.getContacts);
router.post("/", authenticate, ctrl.addContact);
router.delete("/:id", authenticate, ctrl.deleteContact);

module.exports = router;
