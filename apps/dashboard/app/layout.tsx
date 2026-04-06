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
      <body className="bg-[#0f1117] text-[#e1e4ed] min-h-screen antialiased flex flex-col">
        <AuthProvider>
          <main className="flex-1 flex flex-col">
            {children}
          </main>
          
          <footer className="w-full border-t border-[#2a2e3d] bg-[#1a1d27] py-4 px-6 flex flex-col sm:flex-row items-center justify-between text-xs text-[#8b90a0]">
            <div>
              &copy; {new Date().getFullYear()} <span className="font-semibold text-[#e1e4ed]">Sonicverse</span>. Released under the{" "}
              <a href="https://opensource.org/licenses/MIT" target="_blank" rel="noopener noreferrer" className="hover:text-white underline decoration-[#2a2e3d] underline-offset-4">
                MIT License
              </a>.
            </div>
            <div className="mt-2 sm:mt-0 flex items-center gap-4">
              <a href="https://docs.sonicverse.eu" target="_blank" rel="noopener noreferrer" className="flex items-center gap-1.5 hover:text-white transition-colors">
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"></path>
                  <path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"></path>
                </svg>
                Documentation
              </a>
            </div>
          </footer>
        </AuthProvider>
      </body>
    </html>
  );
}
