import type { Metadata } from "next";
import { AuthProvider } from "@/lib/auth";
import "./globals.css";

export const metadata: Metadata = {
  title: "Broadcast Status Panel",
  description: "Real-time streaming infrastructure dashboard",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body className="bg-[#0f1117] text-[#e1e4ed] min-h-screen antialiased">
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
