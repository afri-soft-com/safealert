const { error: logError } = require("./logger");

/** Log the real error server-side; never send stacks or SQL to the client. */
const fail = (res, err, message = "Une erreur est survenue. Réessayez.") => {
  if (err) {
    logError(err.code || "", err.message || String(err));
  }
  return res.status(500).json({ error: message });
};

module.exports = { fail };
