const HASH_KEY = "safealert_admin_pin_hash";
const SALT_KEY = "safealert_admin_pin_salt";
const PHONE_KEY = "safealert_admin_pin_phone";

export const PIN_MIN = 4;
export const PIN_MAX = 6;

export interface PinStore {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

export class MemoryPinStore implements PinStore {
  constructor(private data: Record<string, string> = {}) {}
  getItem(key: string) {
    return this.data[key] ?? null;
  }
  setItem(key: string, value: string) {
    this.data[key] = value;
  }
  removeItem(key: string) {
    delete this.data[key];
  }
}

function bytesToHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function hashPin(pin: string, salt: string): Promise<string> {
  const data = new TextEncoder().encode(`safealert-login:${salt}:${pin}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return bytesToHex(digest);
}

function randomSalt(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function cleanPin(pin: string): string {
  return pin.replace(/\D/g, "");
}

export function isValidPin(pin: string): boolean {
  const cleaned = cleanPin(pin);
  return cleaned.length >= PIN_MIN && cleaned.length <= PIN_MAX;
}

function defaultStore(): PinStore {
  if (typeof window !== "undefined" && window.localStorage) {
    return window.localStorage;
  }
  return new MemoryPinStore();
}

export class LocalPinService {
  constructor(private store: PinStore = defaultStore()) {}

  hasPin(): boolean {
    const h = this.store.getItem(HASH_KEY);
    return !!h;
  }

  storedPhone(): string | null {
    const p = this.store.getItem(PHONE_KEY);
    return p && p.length > 0 ? p : null;
  }

  async setPin(pin: string, phone: string): Promise<void> {
    const cleaned = cleanPin(pin);
    if (!isValidPin(cleaned)) {
      throw new Error("Le code PIN doit contenir 4 à 6 chiffres");
    }
    let salt = this.store.getItem(SALT_KEY);
    if (!salt) {
      salt = randomSalt();
      this.store.setItem(SALT_KEY, salt);
    }
    this.store.setItem(HASH_KEY, await hashPin(cleaned, salt));
    this.store.setItem(PHONE_KEY, phone);
  }

  async verify(pin: string): Promise<boolean> {
    const hash = this.store.getItem(HASH_KEY);
    const salt = this.store.getItem(SALT_KEY);
    if (!hash || !salt) return false;
    const cleaned = cleanPin(pin);
    if (!cleaned) return false;
    return (await hashPin(cleaned, salt)) === hash;
  }

  clear(): void {
    this.store.removeItem(HASH_KEY);
    this.store.removeItem(SALT_KEY);
    this.store.removeItem(PHONE_KEY);
  }
}

export const adminPin = new LocalPinService();
