import { describe, it, expect } from "vitest";
import { normalizePhone } from "../src/utils/phone.js";

describe("normalizePhone", () => {
  it("normalizes DRC local formats to E.164", () => {
    expect(normalizePhone("+243971163574")).toBe("+243971163574");
    expect(normalizePhone("971163574")).toBe("+243971163574");
    expect(normalizePhone("0971163574")).toBe("+243971163574");
    expect(normalizePhone("243971163574")).toBe("+243971163574");
    expect(normalizePhone("+243 97 116 3574")).toBe("+243971163574");
  });

  it("rejects invalid numbers", () => {
    expect(normalizePhone("")).toBeNull();
    expect(normalizePhone("abc")).toBeNull();
    expect(normalizePhone("123")).toBeNull();
  });
});
