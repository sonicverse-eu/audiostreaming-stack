"use client";

import { useState } from "react";
import { useAuth } from "@/lib/auth";

export function LoginForm() {
  const { login } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await login(email, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex-1 flex items-center justify-center">
      <form
        onSubmit={handleSubmit}
        className="bg-[#1a1d27] border border-[#2a2e3d] rounded-xl p-10 w-full max-w-sm"
      >
        <h1 className="text-xl font-semibold mb-1">
          <span className="bg-linear-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent">Sonicverse</span>
          <span className="text-[#8b90a0] mx-2">|</span>
          Status Panel
        </h1>
        <p className="text-[#8b90a0] text-sm mb-6">
          Sign in with your Appwrite account
        </p>

        <input
          type="email"
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="w-full px-3.5 py-2.5 bg-[#0f1117] border border-[#2a2e3d] rounded-lg text-sm mb-3 focus:outline-none focus:border-[#4f8ff7]"
          autoComplete="email"
        />
        <input
          type="password"
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="w-full px-3.5 py-2.5 bg-[#0f1117] border border-[#2a2e3d] rounded-lg text-sm mb-3 focus:outline-none focus:border-[#4f8ff7]"
          autoComplete="current-password"
        />

        <button
          type="submit"
          disabled={loading}
          className="w-full py-2.5 bg-[#4f8ff7] text-white rounded-lg text-sm font-semibold mt-2 hover:opacity-90 disabled:opacity-50"
        >
          {loading ? "Signing in..." : "Sign In"}
        </button>

        {error && <p className="text-[#f87171] text-xs mt-3">{error}</p>}
      </form>
    </div>
  );
}
