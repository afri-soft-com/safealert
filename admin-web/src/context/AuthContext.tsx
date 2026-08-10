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
  saveSession,
  type AuthUser,
} from "../api/client";

interface AuthContextValue {
  user: AuthUser | null;
  isAuthenticated: boolean;
  ready: boolean;
  login: (phone: string, code: string, pseudo?: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(() => {
    const token = getToken();
    const stored = getStoredUser();
    return token && stored?.role === "platform_admin" ? stored : null;
  });
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
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
        if (profile.role !== "platform_admin") {
          clearSession();
          setUser(null);
        } else {
          saveSession(token, profile);
          setUser(profile);
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
  }, []);

  const login = useCallback(async (phone: string, code: string, pseudo?: string) => {
    const { token, user: authUser } = await api.verifyCode(phone, code, pseudo);
    if (authUser.role !== "platform_admin") {
      clearSession();
      throw new Error("Accès réservé aux administrateurs plateforme");
    }
    saveSession(token, authUser);
    setUser(authUser);
  }, []);

  const logout = useCallback(() => {
    clearSession();
    setUser(null);
  }, []);

  const value = useMemo(
    () => ({
      user,
      isAuthenticated: !!user && user.role === "platform_admin",
      ready,
      login,
      logout,
    }),
    [user, ready, login, logout]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth doit être utilisé dans AuthProvider");
  return ctx;
}
