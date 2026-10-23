const { sanitizeSmsPourSerdiPay } = require("../src/services/smsSanitize");

describe("sanitizeSmsPourSerdiPay", () => {
  it("strips sentence punctuation", () => {
    const out = sanitizeSmsPourSerdiPay("Votre code SafeAlert: 123456. Valide 5 minutes!");
    expect(out).not.toMatch(/[.:;!?]/);
    expect(out).toContain("123456");
  });

  it("drops WebOTP / hash lines", () => {
    const out = sanitizeSmsPourSerdiPay(
      "SafeAlert 123456 est votre code Valide 5 min\n@safealert.app #ABCDEF\n<#> junk"
    );
    expect(out).toBe("SafeAlert 123456 est votre code Valide 5 min");
    expect(out).not.toContain("@");
    expect(out).not.toContain("#");
  });

  it("keeps the Reserva-style OTP message intact", () => {
    const msg = "SafeAlert 654321 est votre code Valide 5 min";
    expect(sanitizeSmsPourSerdiPay(msg)).toBe(msg);
  });
});
