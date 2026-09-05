import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  api,
  clearSession,
  getStoredUser,
  getToken,
  isStaffRole,
  saveSession,
  type AuthUser,
} from "../api/client";
import { adminPin } from "../utils/localPin";

interface AuthContextValue {
  user: AuthUser | null;
  isAuthenticated: boolean;
  canEnterConsole: boolean;
  ready: boolean;
  hasLocalPin: boolean;
  pinUnlocked: boolean;
  needsPinSetup: boolean;
  pinPhone: string | null;
  login: (phone: string, code: string, pseudo?: string) => Promise<void>;
  logout: () => void;
  switchPhone: () => void;
  setLocalPin: (pin: string, confirm: string) => Promise<void>;
  unlockWithPin: (pin: string) => Promise<boolean>;
  requestForgotPinCode: () => Promise<{ devCode?: string }>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(() => {
    const token = getToken();
    const stored = getStoredUser();
    return token && stored && isStaffRole(stored.role) ? stored : null;
  });
  const [ready, setReady] = useState(false);
  const [hasLocalPin, setHasLocalPin] = useState(() => adminPin.hasPin());
  const [pinPhone, setPinPhone] = useState<string | null>(() => adminPin.storedPhone());
  const [pinUnlocked, setPinUnlocked] = useState(false);
  const [needsPinSetup, setNeedsPinSetup] = useState(false);

  const refreshPin = useCallback(() => {
    setHasLocalPin(adminPin.hasPin());
    setPinPhone(adminPin.storedPhone());
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      refreshPin();
      const token = getToken();
      if (!token) {
        if (!cancelled) {
          setUser(null);
          setReady(true);
        }
        return;
      }
      try {
        const profile = await api.getProfile();
        if (cancelled) return;
        if (!isStaffRole(profile.role)) {
          clearSession();
          setUser(null);
        } else {
          saveSession(token, profile);
          setUser(profile);
          if (adminPin.hasPin()) {
            const bound = adminPin.storedPhone();
            if (bound && bound !== profile.phone) {
              adminPin.clear();
              refreshPin();
              setNeedsPinSetup(true);
              setPinUnlocked(false);
            } else {
              setNeedsPinSetup(false);
              setPinUnlocked(false);
            }
          } else {
            setNeedsPinSetup(true);
            setPinUnlocked(false);
          }
        }
      } catch {
        if (!cancelled) {
          clearSession();
          setUser(null);
        }
      } finally {
        if (!cancelled) setReady(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [refreshPin]);

  const login = useCallback(
    async (phone: string, code: string, pseudo?: string) => {
      const { token, user: authUser } = await api.verifyCode(phone, code, pseudo);
      if (!isStaffRole(authUser.role)) {
        clearSession();
        throw new Error("Accès réservé aux administrateurs");
      }
      const bound = adminPin.storedPhone();
      if (bound && bound !== authUser.phone) {
        adminPin.clear();
      }
      saveSession(token, authUser);
      setUser(authUser);
      refreshPin();
      setNeedsPinSetup(true);
      setPinUnlocked(false);
    },
    [refreshPin]
  );

  const logout = useCallback(() => {
    setPinUnlocked(false);
    refreshPin();
    if (adminPin.hasPin()) {
      setNeedsPinSetup(false);
    } else if (user) {
      setNeedsPinSetup(true);
    }
  }, [refreshPin, user]);

  const switchPhone = useCallback(() => {
    clearSession();
    adminPin.clear();
    setUser(null);
    setPinUnlocked(false);
    setNeedsPinSetup(false);
    refreshPin();
  }, [refreshPin]);

  const setLocalPin = useCallback(
    async (pin: string, confirm: string) => {
      if (pin !== confirm) {
        throw new Error("Les codes PIN ne correspondent pas");
      }
      const phone = user?.phone || pinPhone;
      if (!phone) {
        throw new Error("Numéro introuvable. Recommencez la connexion.");
      }
      await adminPin.setPin(pin, phone);
      refreshPin();
      setNeedsPinSetup(false);
      setPinUnlocked(true);
    },
    [user, pinPhone, refreshPin]
  );

  const unlockWithPin = useCallback(
    async (pin: string) => {
      const ok = await adminPin.verify(pin);
      if (!ok) return false;
      const token = getToken();
      if (!user && token) {
        try {
          const profile = await api.getProfile();
          if (!isStaffRole(profile.role)) {
            clearSession();
            return false;
          }
          saveSession(token, profile);
          setUser(profile);
        } catch {
          clearSession();
          return false;
        }
      }
      if (!getToken()) return false;
      setPinUnlocked(true);
      setNeedsPinSetup(false);
      return true;
    },
    [user]
  );

  const requestForgotPinCode = useCallback(async () => {
    const phone = adminPin.storedPhone() || user?.phone;
    if (!phone) {
      throw new Error("Aucun numéro enregistré. Saisissez votre numéro.");
    }
    return api.requestCode(phone);
  }, [user]);

  const isAuthenticated =
    !!user && isStaffRole(user.role) && pinUnlocked && !needsPinSetup;
  const canEnterConsole = isAuthenticated;

  const value = useMemo(
    () => ({
      user,
      isAuthenticated,
      canEnterConsole,
      ready,
      hasLocalPin,
      pinUnlocked,
      needsPinSetup,
      pinPhone,
      login,
      logout,
      switchPhone,
      setLocalPin,
      unlockWithPin,
      requestForgotPinCode,
    }),
    [
      user,
      isAuthenticated,
      canEnterConsole,
      ready,
      hasLocalPin,
      pinUnlocked,
      needsPinSetup,
      pinPhone,
      login,
      logout,
      switchPhone,
      setLocalPin,
      unlockWithPin,
      requestForgotPinCode,
    ]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth doit être utilisé dans AuthProvider");
  return ctx;
}
