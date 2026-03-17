import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "heald — Fleet Health Dashboard",
  description: "Live monitoring for all connected Macs. CPU, RAM, Disk, iCloud Sync, Self-Healing.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" data-theme="dark">
      <body
        style={{
          margin: 0,
          background: "#050508",
          color: "rgba(255, 255, 255, 0.88)",
          fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Display', Inter, 'Helvetica Neue', system-ui, sans-serif",
          WebkitFontSmoothing: "antialiased",
        }}
      >
        {children}
      </body>
    </html>
  );
}
