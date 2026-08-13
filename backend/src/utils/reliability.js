/** Map numeric reliability score → French badge for citizens. */
const badgeFromScore = (score) => {
  if (score === null || score === undefined || score === "") {
    return { label: "Nouveau", tier: "new", score: 50 };
  }
  const s = Number(score);
  if (!Number.isFinite(s)) {
    return { label: "Nouveau", tier: "new", score: 50 };
  }
  if (s >= 85) return { label: "Très fiable", tier: "gold", score: s };
  if (s >= 70) return { label: "Fiable", tier: "silver", score: s };
  if (s >= 40) return { label: "Correct", tier: "bronze", score: s };
  return { label: "À confirmer", tier: "low", score: s };
};

const withReliabilityBadge = (row) => {
  if (!row || typeof row !== "object") return row;
  const score = row.reliability_score ?? 50;
  return { ...row, reliability_badge: badgeFromScore(score) };
};

module.exports = { badgeFromScore, withReliabilityBadge };
