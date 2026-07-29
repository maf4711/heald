"use client";

import { MachineCard } from "@/components/MachineCard";
import { t, FleetMachine } from "@/lib/theme";

export function MachineDrawer({
  machine,
  onClose,
}: {
  machine: FleetMachine | null;
  onClose: () => void;
}) {
  if (!machine) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 50,
        display: "flex",
        justifyContent: "flex-end",
        background: "rgba(0,0,0,0.55)",
        backdropFilter: "blur(4px)",
      }}
      onClick={onClose}
    >
      <div
        style={{
          width: "min(520px, 100%)",
          height: "100%",
          overflowY: "auto",
          background: t.bg,
          borderLeft: `1px solid ${t.border}`,
          padding: 16,
          boxShadow: "-12px 0 40px rgba(0,0,0,0.4)",
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            marginBottom: 12,
          }}
        >
          <div style={{ fontSize: 12, color: t.text3, letterSpacing: "0.04em" }}>
            MACHINE DETAIL
          </div>
          <button
            onClick={onClose}
            style={{
              background: t.surface,
              border: `1px solid ${t.border}`,
              color: t.text2,
              borderRadius: 8,
              padding: "6px 12px",
              cursor: "pointer",
              fontSize: 12,
            }}
          >
            Close
          </button>
        </div>
        <MachineCard machine={{ ...machine, history: machine.history ?? [] }} />
      </div>
    </div>
  );
}
