import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "heald — System Health Dashboard",
  description: "Live monitoring dashboard for all connected Macs",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, fontFamily: "system-ui, -apple-system, sans-serif", background: "#0a0a0a", color: "#e5e5e5" }}>
        {children}
      </body>
    </html>
  );
}
