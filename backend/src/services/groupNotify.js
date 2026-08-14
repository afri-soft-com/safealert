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

const notifyUserGroupsOnSOS = async (userId, lat, lng, pseudo, zoneName = null) => {
  const userRes = await pool.query(
    "SELECT sos_notify_groups FROM users WHERE id = $1",
    [userId]
  );
  if (userRes.rows.length === 0 || userRes.rows[0].sos_notify_groups === false) {
    return { groupsNotified: 0, membersNotified: 0 };
  }

  const groups = await pool.query(
    `SELECT g.id, g.name FROM neighborhood_groups g
     JOIN group_members gm ON gm.group_id = g.id
     WHERE gm.user_id = $1`,
    [userId]
  );

  const place = (typeof zoneName === "string" && zoneName.trim())
    ? zoneName.trim()
    : "Lieu en cours de résolution";
  const la = Number(lat);
  const ln = Number(lng);
  const coords =
    Number.isFinite(la) && Number.isFinite(ln)
      ? `${la.toFixed(4)}, ${ln.toFixed(4)}`
      : "";
  const where = coords ? `${place} · ${coords}` : place;

  let membersNotified = 0;
  for (const group of groups.rows) {
    const count = await notifyGroupMembers(
      group.id,
      userId,
      {
        title: "🚨 SOS — membre du groupe",
        body: `${pseudo} a déclenché une alerte SOS dans ${group.name} ! ${where}`,
      },
      {
        type: "group_sos",
        groupId: String(group.id),
        userId: String(userId),
        lat: String(lat),
        lng: String(lng),
        zone_name: zoneName ? String(zoneName) : "",
      }
    );
    membersNotified += count;
  }

  return { groupsNotified: groups.rows.length, membersNotified };
};

module.exports = { notifyGroupMembers, notifyUserGroupsOnSOS };
