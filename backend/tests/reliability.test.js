const { badgeFromScore, withReliabilityBadge } = require("../src/utils/reliability");

describe("reliability badge", () => {
  it("maps score tiers in French", () => {
    expect(badgeFromScore(90).tier).toBe("gold");
    expect(badgeFromScore(90).label).toBe("Très fiable");
    expect(badgeFromScore(75).tier).toBe("silver");
    expect(badgeFromScore(50).tier).toBe("bronze");
    expect(badgeFromScore(20).tier).toBe("low");
    expect(badgeFromScore(null).tier).toBe("new");
  });

  it("attaches badge to incident rows", () => {
    const row = withReliabilityBadge({ id: "1", reliability_score: 88 });
    expect(row.reliability_badge.label).toBe("Très fiable");
    expect(row.reliability_badge.score).toBe(88);
  });
});
