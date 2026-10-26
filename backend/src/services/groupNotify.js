const { pool } = require("../config/database");
const { sendPush } = require("../config/firebase");

const getGroupMemberTokens = async (groupId, excludeUserId = null) => {
  const params = [groupId];
  let excludeClause = "";
  if (excludeUserId) {
    excludeClause = "AND u.id != $2";
    params.push(excludeUserId);
  }
  const result = await pool.query(
    `SELECT u.id, u.fcm_token, u.pseudo
     FROM group_members gm
     JOIN users u ON u.id = gm.user_id
     WHERE gm.group_id = $1 AND u.fcm_token IS NOT NULL ${excludeClause}`,
    params
  );
  return result.rows;
};

const notifyGroupMembers = async (groupId, excludeUserId, notification, data) => {
  const members = await getGroupMemberTokens(groupId, excludeUserId);
  let notified = 0;
  for (const member of members) {
    if (member.fcm_token) {
      await sendPush(member.fcm_token, { notification, data });
      notified += 1;
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
}) => {
  const userRes = await pool.query(
    "SELECT sos_notify_groups FROM users WHERE id = $1",
    [userId]
  );
  if (userRes.rows.length === 0 || userRes.rows[0].sos_notify_groups === false) {
    return { groupsNotified: 0, membersNotified: 0, alertsCreated: 0 };
  }

  const groups = await pool.query(
    `SELECT g.id, g.name FROM neighborhood_groups g
     JOIN group_members gm ON gm.group_id = g.id
     WHERE gm.user_id = $1`,
    [userId]
  );

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
  const feedType = isSos ? "danger" : "danger";

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
      }
    );
    membersNotified += count;
  }

  return { groupsNotified: groups.rows.length, membersNotified, alertsCreated };
};

const notifyUserGroupsOnSOS = (userId, lat, lng, pseudo, zoneName = null) =>
  notifyUserGroups({ userId, lat, lng, pseudo, zoneName, kind: "sos" });

const notifyUserGroupsOnReport = (userId, lat, lng, pseudo, zoneName, incidentType) =>
  notifyUserGroups({
    userId,
    lat,
    lng,
    pseudo,
    zoneName,
    kind: "report",
    incidentType,
  });

module.exports = {
  notifyGroupMembers,
  notifyUserGroups,
  notifyUserGroupsOnSOS,
  notifyUserGroupsOnReport,
};
