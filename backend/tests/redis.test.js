describe("Redis config", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    vi.resetModules();
    process.env = { ...originalEnv };
    delete process.env.REDIS_URL;
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("skips gracefully when REDIS_URL is not set", async () => {
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { initRedis, isRedisReady, cacheGet, cacheSet } = require("../src/config/redis");

    await initRedis();
    expect(isRedisReady()).toBe(false);
    expect(await cacheGet("test")).toBeNull();
    await cacheSet("test", "value");
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining("Redis not configured"));

    warnSpy.mockRestore();
  });

  it("invalidateActiveAlerts is no-op without Redis", async () => {
    const { invalidateActiveAlerts } = require("../src/config/redis");
    await expect(invalidateActiveAlerts()).resolves.toBeUndefined();
  });
});
