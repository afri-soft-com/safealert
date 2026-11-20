const { pool } = require("../config/database");
const { sendPushToUser } = require("./pushTargets");
const { floodAlerts } = require("../config/features");

/**
 * Heavy-rain warnings by area.
 *
 * Every 30 min the server asks Open-Meteo (free, no key) for the next hours
 * of rain on a grid over the city. Users whose last known position lies in a
 * cell with heavy rain coming get one push, at most every COOLDOWN_HOURS.
 * Only grid coordinates are sent to Open-Meteo, never user data.
 */

const FORECAST_URL = "https://api.open-meteo.com/v1/forecast";
const COOLDOWN_HOURS = 12;

const num = (v, d) => {
  const n = Number(v);
  return Number.isFinite(n) ? n : d;
};

/** Defaults cover Kinshasa's urban area. FLOOD_BBOX = "south,west,north,east". */
function config() {
  const [s, w, n, e] = String(process.env.FLOOD_BBOX || "-4.50,15.15,-4.28,15.50")
    .split(",")
    .map((x) => Number(x));
  return {
    south: num(s, -4.5),
    west: num(w, 15.15),
    north: num(n, -4.28),
    east: num(e, 15.5),
    step: Math.max(num(process.env.FLOOD_GRID_STEP, 0.06), 0.02),
    hours: Math.min(Math.max(num(process.env.FLOOD_FORECAST_HOURS, 6), 1), 24),
    mmPerHour: num(process.env.FLOOD_MM_PER_HOUR, 15),
    mm3h: num(process.env.FLOOD_MM_3H, 30),
  };
}

function buildGrid(cfg = config()) {
  const cells = [];
  for (let lat = cfg.south + cfg.step / 2; lat < cfg.north; lat += cfg.step) {
    for (let lng = cfg.west + cfg.step / 2; lng < cfg.east; lng += cfg.step) {
      cells.push({ lat: Number(lat.toFixed(4)), lng: Number(lng.toFixed(4)) });
    }
  }
  return cells;
}

/**
 * Heaviest hour and heaviest 3-hour window for one forecast.
 * Returns { heavy, peakMm, sum3hMm, hoursAhead } — hoursAhead = first heavy hour.
 */
function evaluateRain(precip, cfg = config()) {
  const values = (precip || []).map((v) => num(v, 0));
  let peak = 0;
  let sum3 = 0;
  let firstHeavy = null;
  for (let i = 0; i < values.length; i += 1) {
    if (values[i] > peak) peak = values[i];
    const window = values[i] + (values[i + 1] || 0) + (values[i + 2] || 0);
    if (window > sum3) sum3 = window;
    if (firstHeavy == null && (values[i] >= cfg.mmPerHour || window >= cfg.mm3h)) {
      firstHeavy = i;
    }
  }
  return {
    heavy: firstHeavy != null,
    peakMm: Math.round(peak * 10) / 10,
    sum3hMm: Math.round(sum3 * 10) / 10,
    hoursAhead: firstHeavy,
  };
}

async function fetchForecast(cells, cfg) {
  const url =
    `${FORECAST_URL}?latitude=${cells.map((c) => c.lat).join(",")}` +
    `&longitude=${cells.map((c) => c.lng).join(",")}` +
    `&hourly=precipitation&forecast_hours=${cfg.hours}&timezone=Africa%2FKinshasa`;
  const res = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!res.ok) throw new Error(`open-meteo HTTP ${res.status}`);
  const body = await res.json();
  const list = Array.isArray(body) ? body : [body];
  return list.map((f) => f?.hourly?.precipitation || []);
}

function warningText(rain) {
  const when =
    rain.hoursAhead === 0 ? "maintenant" : `d'ici ${rain.hoursAhead + 1} h`;
  return {
    title: "🌧️ Fortes pluies — risque d'inondation",
    body:
      `Fortes pluies prévues dans votre zone ${when} (jusqu'à ${rain.sum3hMm} mm en 3 h). ` +
      "Évitez les rivières, ravins et caniveaux, et mettez vos papiers à l'abri.",
  };
}

async function processFloodAlerts() {
  if (!floodAlerts()) return { cells: 0, notified: 0 };
  const cfg = config();
  const cells = buildGrid(cfg);
  if (!cells.length) return { cells: 0, notified: 0 };

  const forecasts = await fetchForecast(cells, cfg);
  const heavyCells = [];
  cells.forEach((cell, i) => {
    const rain = evaluateRain(forecasts[i], cfg);
    if (rain.heavy) heavyCells.push({ ...cell, rain });
  });
  if (!heavyCells.length) return { cells: 0, notified: 0 };

  let notified = 0;
  const half = cfg.step / 2;
  for (const cell of heavyCells) {
    // Claim users in the cell so a second run does not warn them again.
    const users = await pool.query(
      `UPDATE users SET flood_alert_sent_at = NOW()
       WHERE last_lat BETWEEN $1 AND $2
         AND last_lng BETWEEN $3 AND $4
         AND last_seen_at > NOW() - INTERVAL '48 hours'
         AND COALESCE(is_active, true) = true
         AND (flood_alert_sent_at IS NULL
              OR flood_alert_sent_at < NOW() - make_interval(hours => $5))
       RETURNING id`,
      [cell.lat - half, cell.lat + half, cell.lng - half, cell.lng + half, COOLDOWN_HOURS]
    );
    const text = warningText(cell.rain);
    for (const u of users.rows) {
      try {
        await sendPushToUser(u.id, {
          notification: text,
          data: {
            type: "flood_alert",
            lat: String(cell.lat),
            lng: String(cell.lng),
            peak_mm: String(cell.rain.peakMm),
            sum3h_mm: String(cell.rain.sum3hMm),
          },
        });
        notified += 1;
      } catch (err) {
        console.error("flood push:", err.message);
      }
    }
  }
  return { cells: heavyCells.length, notified };
}

module.exports = { processFloodAlerts, evaluateRain, buildGrid, config, warningText };
