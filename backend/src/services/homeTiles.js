/**
 * Home-tile visibility for the citizen app (admin kill switches).
 * Defaults: all visible. Env FEATURE_* still gates linked APIs.
 */
const { pool } = require("../config/database");
const features = require("../config/features");

const SETTINGS_KEY = "home_tiles_visibility";

/** Controllable home tiles (order = admin UI order). */
const HOME_TILES = [
  { key: "map", label: "Carte des zones" },
  { key: "contacts", label: "Mes contacts" },
  { key: "annuaire", label: "Urgences" },
  { key: "trip", label: "Trajet sécurisé", feature: "safeTrip" },
  { key: "dashboard", label: "Statistiques" },
  { key: "groups", label: "Groupes voisins" },
  { key: "trust_zones", label: "Zones confiance", feature: "trustZones" },
  { key: "neighborhood", label: "Veille quartier", feature: "neighborhoodWatch" },
  { key: "safety_ping", label: "Je rentre", feature: "arrivalTimer" },
  { key: "live_circles", label: "Cercles famille", feature: "liveCircles" },
  { key: "fake_call", label: "Faux appel", feature: "fakeCall" },
  { key: "safety", label: "Conseils sécurité" },
  { key: "heatmap", label: "Carte chaleur", feature: "heatmap" },
  { key: "history", label: "Mon historique" },
  { key: "help", label: "Aide / Manuel" },
];

const FEATURE_FN = {
  safeTrip: () => features.safeTrip(),
  trustZones: () => features.trustZones(),
  neighborhoodWatch: () => features.neighborhoodWatch(),
  arrivalTimer: () => features.arrivalTimer(),
  liveCircles: () => features.liveCircles(),
  fakeCall: () => features.fakeCall(),
  heatmap: () => features.heatmap(),
};

let cache = { at: 0, overrides: {} };

async function readOverrides() {
  if (Date.now() - cache.at < 5000 && cache.at) {
    return cache.overrides;
  }
  try {
    const r = await pool.query(
      `SELECT value FROM app_settings WHERE key = $1 LIMIT 1`,
      [SETTINGS_KEY]
    );
    const raw = r.rows[0]?.value;
    let overrides = {};
    if (raw) {
      const parsed = typeof raw === "string" ? JSON.parse(raw) : raw;
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        overrides = parsed;
      }
    }
    cache = { at: Date.now(), overrides };
    return overrides;
  } catch (err) {
    if (err.code !== "42P01") {
      console.error("homeTiles read:", err.message);
    }
    return cache.overrides || {};
  }
}

function envAllows(tile) {
  if (!tile.feature) return true;
  const fn = FEATURE_FN[tile.feature];
  return fn ? fn() !== false : true;
}

function adminAllows(overrides, key) {
  if (overrides[key] === false || overrides[key] === "false" || overrides[key] === 0) {
    return false;
  }
  return true;
}

async function getHomeTilesVisibility() {
  const overrides = await readOverrides();
  const visibility = {};
  for (const tile of HOME_TILES) {
    visibility[tile.key] = adminAllows(overrides, tile.key) && envAllows(tile);
  }
  return visibility;
}

async function getHomeTilesAdmin() {
  const overrides = await readOverrides();
  return {
    tiles: HOME_TILES.map((tile) => ({
      key: tile.key,
      label: tile.label,
      visible: adminAllows(overrides, tile.key),
      env_enabled: envAllows(tile),
    })),
  };
}

async function setHomeTilesVisibility(partial) {
  if (!partial || typeof partial !== "object" || Array.isArray(partial)) {
    throw Object.assign(new Error("Payload invalide"), { status: 400 });
  }
  const current = await readOverrides();
  const next = { ...current };
  const allowed = new Set(HOME_TILES.map((t) => t.key));
  for (const [key, value] of Object.entries(partial)) {
    if (!allowed.has(key)) continue;
    if (value === false || value === "false" || value === 0) {
      next[key] = false;
    } else {
      delete next[key];
    }
  }
  await pool.query(
    `INSERT INTO app_settings (key, value, updated_at)
     VALUES ($1, $2, NOW())
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`,
    [SETTINGS_KEY, JSON.stringify(next)]
  );
  cache = { at: 0, overrides: next };
  return getHomeTilesAdmin();
}

/** Invalidate cache (tests). */
function clearHomeTilesCache() {
  cache = { at: 0, overrides: {} };
}

module.exports = {
  HOME_TILES,
  SETTINGS_KEY,
  getHomeTilesVisibility,
  getHomeTilesAdmin,
  setHomeTilesVisibility,
  clearHomeTilesCache,
};
