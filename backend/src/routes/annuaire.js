const { Router } = require("express");
const ctrl = require("../controllers/annuaireController");

const router = Router();

router.get("/", ctrl.getNumbers);

module.exports = router;
