"use client";

import { useState } from "react";

const t = {
  surface: "#0a0a0f",
  border: "rgba(255, 255, 255, 0.04)",
  text1: "rgba(255, 255, 255, 0.88)",
  text2: "rgba(255, 255, 255, 0.45)",
  text3: "rgba(255, 255, 255, 0.2)",
  brand400: "#38bdf8",
  brand500: "#0ea5e9",
  brand900: "#0c4a6e",
  success: "#34d399",
};

const steps = [
  { cmd: "curl -sL https://raw.githubusercontent.com/maf4711/heald/main/install.sh | bash", label: "Install + start" },
];

export function InstallPanel() {
  const [open, setOpen] = useState(false);

  return (
    <div style={{ marginBottom: 16 }}>
      {/* Toggle button */}
      <button
        onClick={() => setOpen(!open)}
        style={{
          display: "flex", alignItems: "center", gap: 8, width: "100%",
          padding: "10px 16px", background: t.surface, border: `1px solid ${t.border}`,
          borderRadius: open ? "12px 12px 0 0" : 12, cursor: "pointer",
          color: t.text2, fontSize: 13, fontWeight: 500,
          transition: "all 200ms cubic-bezier(0.25, 1, 0.5, 1)",
          textAlign: "left",
        }}
      >
        <span style={{
          display: "inline-block", transition: "transform 200ms cubic-bezier(0.25, 1, 0.5, 1)",
          transform: open ? "rotate(90deg)" : "rotate(0)",
          color: t.brand400, fontSize: 12,
        }}>
          &#9654;
        </span>
        <span>Install heald on more Macs</span>
        <code style={{
          marginLeft: "auto", fontSize: 12, color: t.brand400, opacity: open ? 0 : 0.6,
          transition: "opacity 200ms",
          fontFamily: "'SF Mono', 'Fira Code', 'Cascadia Code', monospace",
        }}>
          curl -sL .../install.sh | bash
        </code>
      </button>

      {/* Collapsible content */}
      <div
        style={{
          maxHeight: open ? 400 : 0,
          overflow: "hidden",
          transition: "max-height 300ms cubic-bezier(0.25, 1, 0.5, 1)",
        }}
      >
        <div style={{
          background: t.surface, border: `1px solid ${t.border}`, borderTop: "none",
          borderRadius: "0 0 12px 12px", padding: "16px 20px",
        }}>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {steps.map((step, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <span style={{
                  width: 20, height: 20, borderRadius: "50%", display: "flex",
                  alignItems: "center", justifyContent: "center", flexShrink: 0,
                  background: t.brand400 + "15", color: t.brand400, fontSize: 11, fontWeight: 600,
                }}>
                  {i + 1}
                </span>
                <CopyCmd cmd={step.cmd} />
                <span style={{ fontSize: 11, color: t.text3, flexShrink: 0 }}>{step.label}</span>
              </div>
            ))}
          </div>

          <div style={{
            marginTop: 14, paddingTop: 14, borderTop: `1px solid ${t.border}`,
            display: "flex", gap: 20, fontSize: 11, color: t.text3,
          }}>
            <a href="https://github.com/maf4711/heald" target="_blank" rel="noopener"
              style={{ color: t.brand500, textDecoration: "none" }}>GitHub</a>
            <a href="https://github.com/maf4711/heald/releases" target="_blank" rel="noopener"
              style={{ color: t.brand500, textDecoration: "none" }}>Releases</a>
            <a href="https://github.com/maf4711/homebrew-heald" target="_blank" rel="noopener"
              style={{ color: t.brand500, textDecoration: "none" }}>Homebrew Tap</a>
            <span style={{ marginLeft: "auto" }}>Requires macOS 15+, Xcode 16+ for source build</span>
          </div>
        </div>
      </div>
    </div>
  );
}

function CopyCmd({ cmd }: { cmd: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(cmd);
    } catch {
      const el = document.createElement("textarea");
      el.value = cmd;
      document.body.appendChild(el);
      el.select();
      document.execCommand("copy");
      document.body.removeChild(el);
    }
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div
      onClick={handleCopy}
      style={{
        flex: 1, display: "flex", alignItems: "center", gap: 8,
        padding: "8px 12px", borderRadius: 8, cursor: "pointer",
        background: "#111118", border: `1px solid ${t.border}`,
        fontFamily: "'SF Mono', 'Fira Code', 'Cascadia Code', monospace",
        transition: "border-color 200ms cubic-bezier(0.25, 1, 0.5, 1)",
      }}
      onMouseEnter={(e) => (e.currentTarget.style.borderColor = t.brand400 + "33")}
      onMouseLeave={(e) => (e.currentTarget.style.borderColor = t.border)}
    >
      <span style={{ color: t.success, fontWeight: 600, userSelect: "none" }}>$</span>
      <code style={{ fontSize: 13, color: t.text1, flex: 1, letterSpacing: "0.3px" }}>{cmd}</code>
      <span style={{
        fontSize: 10, color: copied ? t.success : t.text3,
        transition: "color 200ms", flexShrink: 0,
        fontFamily: "-apple-system, sans-serif",
      }}>
        {copied ? "Copied!" : "Copy"}
      </span>
    </div>
  );
}
