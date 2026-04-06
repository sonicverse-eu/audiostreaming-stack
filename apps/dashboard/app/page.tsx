"use client";

import { useAuth } from "@/lib/auth";
import { LoginForm } from "@/components/login-form";
import { Dashboard } from "@/components/dashboard";

export default function Home() {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <div className="text-[#8b90a0] text-sm">Loading...</div>
      </div>
    );
  }

  if (!user) return <LoginForm />;
  return <Dashboard />;
}
