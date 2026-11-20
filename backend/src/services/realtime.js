const jwt = require("jsonwebtoken");
const { pool } = require("../config/database");

/**
 * Socket.IO access control.
 *
 * A socket only joins rooms derived from a verified JWT: `user:<id>`, plus
 * `staff` for leaders, agents and admins. Nothing is broadcast to every
 * connected socket: SOS positions, trips and incident chats go to the people
 * who are allowed to see them over REST.
 */

const STAFF_ROOM = "staff";
const STAFF_ROLES = new Set(["leader", "agent", "admin", "platform_admin"]);

function verifySocketToken(token) {
  if (!token || typeof token !== "string") return null;
  const raw = token.startsWith("Bearer ") ? token.slice(7) : token;
  try {
    const decoded = jwt.verify(raw, process.env.JWT_SECRET);
    if (!decoded || !decoded.userId) return null;
    return { userId: String(decoded.userId), role: decoded.role || null };
  } catch (_) {
    return null;
  }
}

/** Live role and status: a disabled, deleted or demoted account loses its rooms. */
async function loadLiveUser(userId) {
  try {
    const res = await pool.query(
      `SELECT role, COALESCE(is_active, true) AS is_active FROM users WHERE id = $1`,
      [userId]
    );
    if (res.rows.length === 0 || res.rows[0].is_active === false) return null;
    return { role: res.rows[0].role };
  } catch (err) {
    console.error("socket auth lookup:", err.message);
    return null;
  }
}

async function joinRooms(socket, token) {
  const claims = verifySocketToken(token);
  if (!claims) return false;
  const live = await loadLiveUser(claims.userId);
  if (!live) return false;
  socket.data.userId = claims.userId;
  socket.join(`user:${claims.userId}`);
  if (STAFF_ROLES.has(live.role)) socket.join(STAFF_ROOM);
  return true;
}

function tokenFromHandshake(socket) {
  const auth = socket.handshake?.auth || {};
  const header = socket.handshake?.headers?.authorization;
  return auth.token || header || null;
}

/**
 * Sockets without a valid token may connect (older app builds) but join no
 * room, so they receive nothing. `authenticate` accepts `{ token }` only; the
 * old `{ userId }` form is ignored because it proved nothing.
 */
function setupSocketAuth(io) {
  io.on("connection", async (socket) => {
    const token = tokenFromHandshake(socket);
    if (token) await joinRooms(socket, token);

    socket.on("authenticate", async (payload) => {
      if (socket.data.userId) return;
      const t = payload && typeof payload === "object" ? payload.token : null;
      await joinRooms(socket, t);
    });
  });
}

function emitToUsers(io, userIds, event, payload) {
  if (!io) return;
  const seen = new Set();
  for (const id of userIds || []) {
    if (id == null) continue;
    const key = String(id);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    io.to(`user:${key}`).emit(event, payload);
  }
}

function emitToStaff(io, event, payload) {
  if (!io) return;
  io.to(STAFF_ROOM).emit(event, payload);
}

/** App users the sender listed as trust contacts. */
async function trustContactUserIds(userId) {
  try {
    const res = await pool.query(
      `SELECT contact_user_id FROM trust_contacts
       WHERE user_id = $1 AND contact_user_id IS NOT NULL`,
      [userId]
    );
    return res.rows.map((r) => r.contact_user_id);
  } catch (err) {
    console.error("trustContactUserIds:", err.message);
    return [];
  }
}

/** Sender's trust contacts and staff, never the sender's own room. */
async function emitToTrustCircle(io, senderId, event, payload) {
  if (!io) return;
  const ids = (await trustContactUserIds(senderId)).filter(
    (id) => String(id) !== String(senderId)
  );
  // One chained broadcast so a staff member who is also a contact gets it once.
  let target = io.to(STAFF_ROOM);
  for (const id of new Set(ids.map(String))) target = target.to(`user:${id}`);
  target.emit(event, payload);
}

module.exports = {
  STAFF_ROOM,
  STAFF_ROLES,
  verifySocketToken,
  setupSocketAuth,
  emitToUsers,
  emitToStaff,
  emitToTrustCircle,
  trustContactUserIds,
};
