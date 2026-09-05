import { describe, expect, it } from "vitest";
import { LocalPinService, MemoryPinStore, hashPin, isValidPin } from "./localPin";

describe("admin local PIN", () => {
  it("rejects PIN shorter than 4 or longer than 6", () => {
    expect(isValidPin("123")).toBe(false);
    expect(isValidPin("1234567")).toBe(false);
    expect(isValidPin("1357")).toBe(true);
    expect(isValidPin("135790")).toBe(true);
  });

  it("stores a hash, never the raw PIN", async () => {
    const store = new MemoryPinStore();
    const pins = new LocalPinService(store);
    await pins.setPin("246810", "+243971163574");

    const dumped = JSON.stringify(store);
    expect(dumped).not.toContain("246810");
    expect(pins.hasPin()).toBe(true);
    expect(pins.storedPhone()).toBe("+243971163574");
  });

  it("verify accepts the same PIN and rejects another", async () => {
    const pins = new LocalPinService(new MemoryPinStore());
    await pins.setPin("135790", "+243811234567");
    expect(await pins.verify("135790")).toBe(true);
    expect(await pins.verify("000000")).toBe(false);
  });

  it("survives logout-style reuse of the same store", async () => {
    const store = new MemoryPinStore();
    const first = new LocalPinService(store);
    await first.setPin("112233", "+243812345678");

    const afterLogout = new LocalPinService(store);
    expect(afterLogout.hasPin()).toBe(true);
    expect(await afterLogout.verify("112233")).toBe(true);
    expect(afterLogout.storedPhone()).toBe("+243812345678");
  });

  it("clear removes PIN binding for changer de numéro", async () => {
    const store = new MemoryPinStore();
    const pins = new LocalPinService(store);
    await pins.setPin("112233", "+243812345678");
    pins.clear();
    expect(pins.hasPin()).toBe(false);
    expect(pins.storedPhone()).toBeNull();
    expect(await pins.verify("112233")).toBe(false);
  });

  it("hash is deterministic for the same salt", async () => {
    const a = await hashPin("1234", "abcd");
    const b = await hashPin("1234", "abcd");
    const c = await hashPin("1234", "abce");
    expect(a).toBe(b);
    expect(a).not.toBe(c);
  });
});
