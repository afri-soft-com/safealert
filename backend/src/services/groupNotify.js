const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");
const { sendSMS } = require("./sms");

/**
 * Active FCM tokens for group members (users.fcm_token ∪ user_devices).
 */
const getGroupMemberTokens = async (groupId, excludeUserId = null) => {
  const params = [groupId];
  let excludeClause = "";
  if (excludeUserId) {
    excludeClause = "AND u.id::text <> $2::text";
    params.push(String(excludeUserId));
  }
  const result = await pool.query(
    `SELECT u.id, u.pseudo, t.fcm_token
     FROM group_members gm
     JOIN users u ON u.id = gm.user_id
     JOIN (
       SELECT id AS user_id, fcm_token
         FROM users
        WHERE fcm_token IS NOT NULL AND length(trim(fcm_token)) > 0
       UNION
       SELECT user_id, fcm_token
         FROM user_devices
        WHERE revoked_at IS NULL
          AND fcm_token IS NOT NULL
          AND length(trim(fcm_token)) > 0
     ) t ON t.user_id = u.id
     WHERE gm.group_id = $1 ${excludeClause}`,
    params
  );
  return result.rows;
};

/** Members (with phone) for SMS / socket — even without FCM. */
const getGroupMembersContactable = async (groupId, excludeUserId = null) => {
  const params = [groupId];
  let excludeClause = "";
  if (excludeUserId) {
    excludeClause = "AND u.id::text <> $2::text";
    params.push(String(excludeUserId));
  }
  const result = await pool.query(
    `SELECT u.id, u.pseudo, u.phone
     FROM group_members gm
     JOIN users u ON u.id = gm.user_id
     WHERE gm.group_id = $1 ${excludeClause}`,
    params
  );
  return result.rows;
};

const notifyGroupMembers = async (
  groupId,
  excludeUserId,
  notification,
  data,
  io = null,
  { sms = false } = {}
) => {
  const tokenRows = await getGroupMemberTokens(groupId, excludeUserId);
  let pushNotified = 0;
  const seenTokens = new Set();
  for (const member of tokenRows) {
    const token = member.fcm_token;
    if (!token || seenTokens.has(token)) continue;
    seenTokens.add(token);
    const ok = await sendPush(token, { notification, data });
    if (ok) pushNotified += 1;
  }

  let smsNotified = 0;
  if (sms) {
    const members = await getGroupMembersContactable(groupId, excludeUserId);
    const smsBody = `🔴 SafeAlert — ${notification?.body || "Alerte SOS d'un membre du groupe"}`;
    for (const member of members) {
      if (!member.phone) continue;
      try {
        await sendSMS(member.phone, smsBody);
        smsNotified += 1;
      } catch (err) {
        console.error("group SOS SMS failed:", member.id, err.message);
      }
    }
  }

  // Online members: realtime even without FCM.
  if (io) {
    try {
      const members = await getGroupMembersContactable(groupId, excludeUserId);
      const payload = {
        ...(data || {}),
        title: notification?.title,
        body: notification?.body,
      };
      for (const member of members) {
        const uid = member.id;
        io.to(`user:${uid}`).emit("group_sos", payload);
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

  return { pushNotified, smsNotified, membersNotified: pushNotified + smsNotified };
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
  return true;
};

/**
 * Push (+ SMS for SOS) + feed Alertes for every neighborhood group.
 * Gated by users.sos_notify_groups.
 */
const notifyUserGroups = async ({
  userId,
  lat,
  lng,
  pseudo,
  zoneName = null,
  kind = "sos",
  incidentType = null,
  io = null,
}) => {
  const userRes = await pool.query(
    "SELECT sos_notify_groups FROM users WHERE id = $1",
    [userId]
  );
  if (userRes.rows.length === 0 || !groupsNotifyEnabled(userRes.rows[0].sos_notify_groups)) {
    console.log("groupNotify skipped (disabled or missing user)", {
      userId,
      sos_notify_groups: userRes.rows[0]?.sos_notify_groups,
    });
    return {
      groupsNotified: 0,
      membersNotified: 0,
      alertsCreated: 0,
      pushNotified: 0,
      smsNotified: 0,
      otherMembers: 0,
      disabled: true,
    };
  }

  const groups = await pool.query(
    `SELECT g.id, g.name FROM neighborhood_groups g
     JOIN group_members gm ON gm.group_id = g.id
     WHERE gm.user_id = $1`,
    [userId]
  );

  if (groups.rows.length === 0) {
    console.log("groupNotify: user has no neighborhood groups", { userId });
    return {
      groupsNotified: 0,
      membersNotified: 0,
      alertsCreated: 0,
      pushNotified: 0,
      smsNotified: 0,
      otherMembers: 0,
    };
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

  let membersNotified = 0;
  let pushNotified = 0;
  let smsNotified = 0;
  let alertsCreated = 0;
  let otherMembers = 0;
  for (const group of groups.rows) {
    try {
      await pool.query(
        `INSERT INTO group_alerts (group_id, author_id, type, title, body, lat, lng)
         VALUES ($1, $2, 'danger', $3, $4, $5, $6)`,
        [group.id, userId, alertTitle, alertBody(group.name), la, ln]
      );
      alertsCreated += 1;
    } catch (err) {
      console.error("group alert insert failed:", group.id, err.message);
    }

    try {
      const peers = await getGroupMembersContactable(group.id, userId);
      otherMembers += peers.length;

      const result = await notifyGroupMembers(
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
        io,
        { sms: isSos }
      );
      pushNotified += result.pushNotified || 0;
      smsNotified += result.smsNotified || 0;
      membersNotified += result.membersNotified || 0;
    } catch (err) {
      console.error("group member notify failed:", group.id, err.message);
    }
  }

  console.log("groupNotify done", {
    userId,
    kind,
    groupsNotified: groups.rows.length,
    otherMembers,
    membersNotified,
    pushNotified,
    smsNotified,
    alertsCreated,
  });

  return {
    groupsNotified: groups.rows.length,
    otherMembers,
    membersNotified,
    pushNotified,
    smsNotified,
    alertsCreated,
    alone: otherMembers === 0 && groups.rows.length > 0,
  };
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
