import {
  createContext,
  useCallback,
  useContext,
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
  login: (phone: string, code: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(() => {
    const token = getToken();
    const stored = getStoredUser();
    return token && stored?.role === "platform_admin" ? stored : null;
  });

  const login = useCallback(async (phone: string, code: string) => {
    const { token, user: authUser } = await api.verifyCode(phone, code);
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
      isAuthenticated: !!user,
      login,
      logout,
    }),
    [user, login, logout]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth doit être utilisé dans AuthProvider");
  return ctx;
}
