"use client";

import { useState } from "react";

const steps = [
  {
    label: "Install heald",
    cmd: "brew install maf4711/heald/heald",
    note: "Installs the self-healing daemon via Homebrew",
  },
  {
    label: "Start daemon",
    cmd: "$(brew --prefix heald)/install.sh",
    note: "Configures and starts the LaunchAgent",
  },
];

export function InstallHero() {
  return (
    <div style={{ textAlign: "center", padding: "48px 16px 64px" }}>
      {/* Tagline */}
      <p style={{
        fontSize: 14, color: "#22c55e", fontWeight: 600, letterSpacing: 1.5,
        textTransform: "uppercase", marginBottom: 8,
      }}>
        Self-healing macOS daemon
      </p>

      <h2 style={{ fontSize: 36, fontWeight: 700, margin: "0 0 12px", lineHeight: 1.2 }}>
        Monitor, heal and protect<br />every Mac in your fleet.
      </h2>

      <p style={{ fontSize: 16, color: "#888", maxWidth: 600, margin: "0 auto 40px" }}>
        CPU, RAM, Disk, Processes, iCloud Sync, SMART, Thermal &mdash; all in one daemon.<br />
        Auto-kills runaway processes. Downloads missing iCloud files. Pushes metrics here.
      </p>

      {/* Install Commands */}
      <div style={{ maxWidth: 540, margin: "0 auto", display: "flex", flexDirection: "column", gap: 12 }}>
        {steps.map((step, i) => (
          <div key={i}>
            <div style={{ fontSize: 11, color: "#666", marginBottom: 4, textAlign: "left" }}>
              {i + 1}. {step.label}
            </div>
            <CopyableCommand cmd={step.cmd} />
            <div style={{ fontSize: 11, color: "#555", marginTop: 4, textAlign: "left" }}>
              {step.note}
            </div>
          </div>
        ))}
      </div>

      {/* Feature Grid */}
      <div style={{
        display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
        gap: 12, maxWidth: 700, margin: "48px auto 0", textAlign: "left",
      }}>
        <Feature title="CPU & RAM" desc="Per-core usage, swap spikes, memory pressure" />
        <Feature title="Disk & SMART" desc="Space, I/O throughput, drive health" />
        <Feature title="iCloud Sync" desc="File counts, evicted dirs, conflicts, bird daemon" />
        <Feature title="Self-Healing" desc="Auto-kills CPU hogs, downloads cloud files" />
        <Feature title="100+ Macs" desc="Fleet dashboard with search, sort, alerts" />
        <Feature title="Ollama AI" desc="Optional AI-powered health decisions" />
      </div>

      {/* Links */}
      <div style={{ marginTop: 40, display: "flex", gap: 24, justifyContent: "center", fontSize: 13 }}>
        <a href="https://github.com/maf4711/heald" target="_blank" rel="noopener"
          style={{ color: "#3b82f6", textDecoration: "none" }}>
          GitHub
        </a>
        <a href="https://github.com/maf4711/heald/releases" target="_blank" rel="noopener"
          style={{ color: "#3b82f6", textDecoration: "none" }}>
          Releases
        </a>
        <a href="https://github.com/maf4711/homebrew-heald" target="_blank" rel="noopener"
          style={{ color: "#3b82f6", textDecoration: "none" }}>
          Homebrew Tap
        </a>
      </div>
    </div>
  );
}

function CopyableCommand({ cmd }: { cmd: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(cmd);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback
      const el = document.createElement("textarea");
      el.value = cmd;
      document.body.appendChild(el);
      el.select();
      document.execCommand("copy");
      document.body.removeChild(el);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  return (
    <div
      onClick={handleCopy}
      style={{
        display: "flex", alignItems: "center", justifyContent: "space-between",
        background: "#1a1a1a", border: "1px solid #333", borderRadius: 10,
        padding: "14px 18px", cursor: "pointer", transition: "border-color .2s",
        fontFamily: "'SF Mono', 'Fira Code', 'Cascadia Code', monospace",
      }}
      onMouseEnter={(e) => (e.currentTarget.style.borderColor = "#555")}
      onMouseLeave={(e) => (e.currentTarget.style.borderColor = "#333")}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <span style={{ color: "#22c55e", fontWeight: 600, userSelect: "none" }}>$</span>
        <code style={{ fontSize: 15, color: "#eee", letterSpacing: 0.3 }}>{cmd}</code>
      </div>
      <span style={{
        fontSize: 11, color: copied ? "#22c55e" : "#666",
        fontFamily: "system-ui", transition: "color .2s", flexShrink: 0, marginLeft: 12,
      }}>
        {copied ? "Copied!" : "Click to copy"}
      </span>
    </div>
  );
}

function Feature({ title, desc }: { title: string; desc: string }) {
  return (
    <div style={{ background: "#1a1a1a", borderRadius: 8, padding: "14px 16px", border: "1px solid #222" }}>
      <div style={{ fontSize: 13, fontWeight: 600, color: "#eee", marginBottom: 4 }}>{title}</div>
      <div style={{ fontSize: 11, color: "#888", lineHeight: 1.4 }}>{desc}</div>
    </div>
  );
}
