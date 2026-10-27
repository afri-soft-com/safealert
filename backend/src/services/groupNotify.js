const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");

/**
 * All active FCM tokens for group members (users.fcm_token + user_devices).
 * Multi-device: each active device token is returned as its own row.
 */
const getGroupMemberTokens = async (groupId, excludeUserId = null) => {
  const params = [groupId];
  let excludeClause = "";
  if (excludeUserId) {
    excludeClause = "AND u.id <> $2";
    params.push(excludeUserId);
  }
  const result = await pool.query(
    `SELECT DISTINCT ON (token)
            u.id, u.pseudo, token AS fcm_token
     FROM group_members gm
     JOIN users u ON u.id = gm.user_id
     CROSS JOIN LATERAL (
       SELECT u.fcm_token AS token
       WHERE u.fcm_token IS NOT NULL AND length(trim(u.fcm_token)) > 0
       UNION
       SELECT ud.fcm_token
       FROM user_devices ud
       WHERE ud.user_id = u.id
         AND ud.revoked_at IS NULL
         AND ud.fcm_token IS NOT NULL
         AND length(trim(ud.fcm_token)) > 0
     ) t(token)
     WHERE gm.group_id = $1 ${excludeClause}
     ORDER BY token, u.id`,
    params
  );
  return result.rows;
};

/** Member user ids (for socket rooms), with or without FCM. */
const getGroupMemberIds = async (groupId, excludeUserId = null) => {
  const params = [groupId];
  let excludeClause = "";
  if (excludeUserId) {
    excludeClause = "AND user_id <> $2";
    params.push(excludeUserId);
  }
  const result = await pool.query(
    `SELECT user_id FROM group_members WHERE group_id = $1 ${excludeClause}`,
    params
  );
  return result.rows.map((r) => r.user_id);
};

const notifyGroupMembers = async (groupId, excludeUserId, notification, data, io = null) => {
  const members = await getGroupMemberTokens(groupId, excludeUserId);
  let notified = 0;
  const seenTokens = new Set();
  for (const member of members) {
    const token = member.fcm_token;
    if (!token || seenTokens.has(token)) continue;
    seenTokens.add(token);
    const ok = await sendPush(token, { notification, data });
    if (ok) notified += 1;
  }

  // Online members without a usable FCM token still get a realtime event.
  if (io) {
    try {
      const ids = await getGroupMemberIds(groupId, excludeUserId);
      const payload = {
        ...(data || {}),
        title: notification?.title,
        body: notification?.body,
      };
      for (const uid of ids) {
        io.to(`user:${uid}`).emit("group_sos", payload);
        // Reuse existing client handler so siren plays for online members.
        if (data?.type === "group_sos" || data?.type === "group_report") {
          io.to(`user:${uid}`).emit("sos_alert", {
            user_id: data.userId,
            lat: data.lat != null ? Number(data.lat) : null,
            lng: data.lng != null ? Number(data.lng) : null,
            zone_name: data.zone_name || null,
            incident_type: data.type,
            group_id: data.groupId,
          });
        }
      }
    } catch (err) {
      console.error("group socket notify failed:", err.message);
    }
  }

  return notified;
};

const locationWhere = (lat, lng, zoneName) => {
  const place =
    typeof zoneName === "string" && zoneName.trim()
      ? zoneName.trim()
      : "Lieu en cours de résolution";
  const la = Number(lat);
  const ln = Number(lng);
  const coords =
    Number.isFinite(la) && Number.isFinite(ln)
      ? `${la.toFixed(4)}, ${ln.toFixed(4)}`
      : "";
  return {
    where: coords ? `${place} · ${coords}` : place,
    la: Number.isFinite(la) ? la : null,
    ln: Number.isFinite(ln) ? ln : null,
  };
};

const groupsNotifyEnabled = (value) => {
  if (value === false || value === 0) return false;
  if (typeof value === "string") {
    const v = value.trim().toLowerCase();
    if (["0", "false", "no", "off", "f"].includes(v)) return false;
  }
  // null / undefined / true → on (DB default true)
  return true;
};

/**
 * Push + feed Alertes for every neighborhood group the user belongs to.
 * Gated by users.sos_notify_groups (covers SOS and signalements).
 */
const notifyUserGroups = async ({
  userId,
  lat,
  lng,
  pseudo,
  zoneName = null,
  kind = "sos", // sos | report
  incidentType = null,
  io = null,
}) => {
  const userRes = await pool.query(
    "SELECT sos_notify_groups FROM users WHERE id = $1",
    [userId]
  );
  if (userRes.rows.length === 0 || !groupsNotifyEnabled(userRes.rows[0].sos_notify_groups)) {
    console.log("groupNotify skipped (disabled or missing user)", { userId });
    return { groupsNotified: 0, membersNotified: 0, alertsCreated: 0 };
  }

  const groups = await pool.query(
    `SELECT g.id, g.name FROM neighborhood_groups g
     JOIN group_members gm ON gm.group_id = g.id
     WHERE gm.user_id = $1`,
    [userId]
  );

  if (groups.rows.length === 0) {
    console.log("groupNotify: user has no neighborhood groups", { userId });
    return { groupsNotified: 0, membersNotified: 0, alertsCreated: 0 };
  }

  const { where, la, ln } = locationWhere(lat, lng, zoneName);
  const isSos = kind !== "report";
  const typeLabel = incidentType ? String(incidentType) : "incident";
  const alertTitle = isSos ? `SOS — ${pseudo}` : `Signalement — ${typeLabel}`;
  const alertBody = isSos
    ? (groupName) => `Alerte SOS déclenchée dans ${groupName}. ${where}`
    : (groupName) => `${pseudo} a signalé « ${typeLabel} » dans ${groupName}. ${where}`;
  const pushTitle = isSos ? "🚨 SOS — membre du groupe" : "⚠️ Signalement — groupe";
  const pushBody = isSos
    ? (groupName) => `${pseudo} a déclenché une alerte SOS dans ${groupName} ! ${where}`
    : (groupName) => `${pseudo} a signalé « ${typeLabel} » dans ${groupName}. ${where}`;
  const pushType = isSos ? "group_sos" : "group_report";
  const feedType = "danger";

  let membersNotified = 0;
  let alertsCreated = 0;
  for (const group of groups.rows) {
    try {
      await pool.query(
        `INSERT INTO group_alerts (group_id, author_id, type, title, body, lat, lng)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [group.id, userId, feedType, alertTitle, alertBody(group.name), la, ln]
      );
      alertsCreated += 1;
    } catch (err) {
      console.error("group alert insert failed:", group.id, err.message);
    }

    const count = await notifyGroupMembers(
      group.id,
      userId,
      {
        title: pushTitle,
        body: pushBody(group.name),
      },
      {
        type: pushType,
        groupId: String(group.id),
        userId: String(userId),
        lat: String(lat),
        lng: String(lng),
        zone_name: zoneName ? String(zoneName) : "",
        incidentType: incidentType ? String(incidentType) : "",
      },
      io
    );
    membersNotified += count;
  }

  console.log("groupNotify done", {
    userId,
    kind,
    groupsNotified: groups.rows.length,
    membersNotified,
    alertsCreated,
  });

  return { groupsNotified: groups.rows.length, membersNotified, alertsCreated };
};

const notifyUserGroupsOnSOS = (userId, lat, lng, pseudo, zoneName = null, io = null) =>
  notifyUserGroups({ userId, lat, lng, pseudo, zoneName, kind: "sos", io });

const notifyUserGroupsOnReport = (userId, lat, lng, pseudo, zoneName, incidentType, io = null) =>
  notifyUserGroups({
    userId,
    lat,
    lng,
    pseudo,
    zoneName,
    kind: "report",
    incidentType,
    io,
  });

module.exports = {
  notifyGroupMembers,
  notifyUserGroups,
  notifyUserGroupsOnSOS,
  notifyUserGroupsOnReport,
  getGroupMemberTokens,
  groupsNotifyEnabled,
};
