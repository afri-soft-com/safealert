const { estimateEtaMinutes, normalizeTransportMode } = require("../src/utils/geo");

describe("trip ETA", () => {
  it("normalizes transport aliases", () => {
    expect(normalizeTransportMode("pied")).toBe("walk");
    expect(normalizeTransportMode("voiture")).toBe("car");
    expect(normalizeTransportMode("")).toBe("moto");
  });

  it("walk is slower than moto on the same path", () => {
    const walk = estimateEtaMinutes(-4.3276, 15.3136, -4.35, 15.35, "walk");
    const moto = estimateEtaMinutes(-4.3276, 15.3136, -4.35, 15.35, "moto");
    expect(walk).toBeGreaterThan(moto);
    expect(moto).toBeGreaterThanOrEqual(5);
  });
});
