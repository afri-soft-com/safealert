import { describe, it, expect, beforeEach, vi, afterEach } from "vitest";
import { pickZoneName, reverseGeocode, clearGeocodeCache } from "../src/services/geocode.js";

describe("geocode service", () => {
  beforeEach(() => {
    clearGeocodeCache();
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
  });

  it("pickZoneName prefers suburb then city", () => {
    expect(pickZoneName({ suburb: "Gombe", city: "Kinshasa" })).toBe("Gombe");
    expect(pickZoneName({ city: "Kinshasa" })).toBe("Kinshasa");
    expect(pickZoneName({})).toBeNull();
  });

  it("reverseGeocode caches results", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ address: { neighbourhood: "Limete" } }),
    });
    vi.stubGlobal("fetch", fetchMock);

    const p1 = reverseGeocode(-4.32, 15.31);
    await vi.runAllTimersAsync();
    const zone1 = await p1;

    const p2 = reverseGeocode(-4.32, 15.31);
    await vi.runAllTimersAsync();
    const zone2 = await p2;

    expect(zone1).toBe("Limete");
    expect(zone2).toBe("Limete");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0][1].headers["User-Agent"]).toContain("SafeAlert");
  });

  it("reverseGeocode returns null for invalid coords", async () => {
    const result = await reverseGeocode("bad", "data");
    expect(result).toBeNull();
  });
});
