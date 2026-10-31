const { pool } = require("../config/database");
const { sendPushToUser } = require("./pushTargets");
const { sendSMS } = require("./sms");

/** Distinct member user ids (for push via sendPushToUser → FCM and/or APNs). */
const getGroupMemberUserIds = async (groupId, excludeUserId = null) => {
  const params = [groupId];
  let excludeClause = "";
  if (excludeUserId) {
    excludeClause = "AND u.id::text <> $2::text";
    params.push(String(excludeUserId));
  }
  const result = await pool.query(
    `SELECT DISTINCT u.id, u.pseudo
     FROM group_members gm
     JOIN users u ON u.id = gm.user_id
     WHERE gm.group_id = $1 ${excludeClause}`,
    params
  );
  return result.rows;
};

/** @deprecated kept for tests — prefer getGroupMemberUserIds */
const getGroupMemberTokens = getGroupMemberUserIds;

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
  const members = await getGroupMemberUserIds(groupId, excludeUserId);
  let pushNotified = 0;
  const seenUsers = new Set();
  for (const member of members) {
    const uid = member.id;
    if (!uid || seenUsers.has(uid)) continue;
    seenUsers.add(uid);
    const n = await sendPushToUser(uid, { notification, data });
    if (n > 0) pushNotified += 1;
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
      const critical =
        data?.type === "group_sos" ||
        data?.type === "group_report" ||
        data?.type === "safety_ping_missed";
      for (const member of members) {
        const uid = member.id;
        // Resolutions (false alarm / safe) must not trigger the SOS siren path.
        io.to(`user:${uid}`).emit(critical ? "group_sos" : "group_resolution", payload);
        if (critical) {
          io.to(`user:${uid}`).emit("sos_alert", {
            user_id: data.userId,
            lat: data.lat != null ? Number(data.lat) : null,
            lng: data.lng != null ? Number(data.lng) : null,
            zone_name: data.zone_name || null,
            incident_type: data.type,
            group_id: data.groupId,
            phone: data.phone || "",
            pseudo: data.pseudo || "",
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
    "SELECT sos_notify_groups, pseudo, phone FROM users WHERE id = $1",
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
  const senderPseudo = userRes.rows[0].pseudo || pseudo || "Un membre";
  const senderPhone = userRes.rows[0].phone ? String(userRes.rows[0].phone) : "";

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
  const typeLabel = incidentType ? String(incidentType) : "incident";
  const copy = groupNotifyCopy(kind, pseudo, typeLabel, where);
  const withSms = kind === "sos" || kind === "false_alarm" || kind === "safe";

  let membersNotified = 0;
  let pushNotified = 0;
  let smsNotified = 0;
  let alertsCreated = 0;
  let otherMembers = 0;
  for (const group of groups.rows) {
    try {
      await pool.query(
        `INSERT INTO group_alerts (group_id, author_id, type, title, body, lat, lng)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [group.id, userId, copy.feedType, copy.alertTitle, copy.alertBody(group.name), la, ln]
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
          title: copy.pushTitle,
          body: copy.pushBody(group.name),
        },
        {
          type: copy.pushType,
          groupId: String(group.id),
          userId: String(userId),
          pseudo: String(senderPseudo),
          phone: senderPhone,
          lat: String(lat ?? ""),
          lng: String(lng ?? ""),
          zone_name: zoneName ? String(zoneName) : "",
          incidentType: incidentType ? String(incidentType) : "",
        },
        io,
        { sms: withSms }
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

const groupNotifyCopy = (kind, pseudo, typeLabel, where) => {
  if (kind === "false_alarm") {
    return {
      feedType: "info",
      alertTitle: `Fausse alerte — ${pseudo}`,
      alertBody: (groupName) =>
        `${pseudo} a annulé son SOS dans le groupe « ${groupName} ». Situation sous contrôle. ${where}`,
      pushTitle: "✅ Fausse alerte — groupe",
      pushBody: (groupName) =>
        `Groupe « ${groupName} » : ${pseudo} a annulé son SOS. ${where}`,
      pushType: "group_false_alarm",
    };
  }
  if (kind === "safe") {
    return {
      feedType: "info",
      alertTitle: `En sécurité — ${pseudo}`,
      alertBody: (groupName) =>
        `${pseudo} confirme être en sécurité (groupe « ${groupName} »). ${where}`,
      pushTitle: "✅ En sécurité — groupe",
      pushBody: (groupName) =>
        `Groupe « ${groupName} » : ${pseudo} confirme être en sécurité. ${where}`,
      pushType: "group_safe",
    };
  }
  if (kind === "report") {
    return {
      feedType: "danger",
      alertTitle: `Signalement — ${typeLabel}`,
      alertBody: (groupName) =>
        `${pseudo} a signalé « ${typeLabel} » dans le groupe « ${groupName} ». ${where}`,
      pushTitle: "⚠️ Signalement — groupe",
      pushBody: (groupName) =>
        `Groupe « ${groupName} » : ${pseudo} a signalé « ${typeLabel} ». ${where}`,
      pushType: "group_report",
    };
  }
  return {
    feedType: "danger",
    alertTitle: `SOS — ${pseudo}`,
    alertBody: (groupName) =>
      `SOS déclenché dans le groupe « ${groupName} ». ${where}`,
    pushTitle: "🚨 SOS — groupe",
    pushBody: (groupName) =>
      `Groupe « ${groupName} » : ${pseudo} a déclenché un SOS ! ${where}`,
    pushType: "group_sos",
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

const notifyUserGroupsOnFalseAlarm = (userId, lat, lng, pseudo, zoneName = null, io = null) =>
  notifyUserGroups({ userId, lat, lng, pseudo, zoneName, kind: "false_alarm", io });

const notifyUserGroupsOnSafe = (userId, lat, lng, pseudo, zoneName = null, io = null) =>
  notifyUserGroups({ userId, lat, lng, pseudo, zoneName, kind: "safe", io });

module.exports = {
  notifyGroupMembers,
  notifyUserGroups,
  notifyUserGroupsOnSOS,
  notifyUserGroupsOnReport,
  notifyUserGroupsOnFalseAlarm,
  notifyUserGroupsOnSafe,
  getGroupMemberTokens,
  groupsNotifyEnabled,
};
