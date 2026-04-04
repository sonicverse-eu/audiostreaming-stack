"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
} from "react";
import type { Models } from "appwrite";
import { account } from "./appwrite";

interface AuthContextType {
  user: Models.User<Models.Preferences> | null;
  jwt: string | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  user: null,
  jwt: null,
  loading: true,
  login: async () => {},
  logout: async () => {},
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<Models.User<Models.Preferences> | null>(
    null
  );
  const [jwt, setJwt] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const authenticate = useCallback(async () => {
    try {
      const currentUser = await account.get();
      const jwtResp = await account.createJWT();

      // Verify team access via API
      const API_URL = process.env.NEXT_PUBLIC_API_URL || "";
      const res = await fetch(`${API_URL}/api/status`, {
        headers: { Authorization: `Bearer ${jwtResp.jwt}` },
      });
      if (res.status === 401) {
        await account.deleteSession("current");
        throw new Error(
          "Access denied. You must be a member of the broadcast team."
        );
      }

      setUser(currentUser);
      setJwt(jwtResp.jwt);
    } catch {
      setUser(null);
      setJwt(null);
    }
  }, []);

  useEffect(() => {
    authenticate().finally(() => setLoading(false));
  }, [authenticate]);

  const login = useCallback(
    async (email: string, password: string) => {
      await account.createEmailPasswordSession(email, password);
      await authenticate();
      if (!jwt) {
        throw new Error(
          "Access denied. You must be a member of the broadcast team."
        );
      }
    },
    [authenticate, jwt]
  );

  const logout = useCallback(async () => {
    try {
      await account.deleteSession("current");
    } catch {}
    setUser(null);
    setJwt(null);
  }, []);

  return (
    <AuthContext.Provider value={{ user, jwt, loading, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
