"use client";

import { t } from "@/lib/theme";

const PAGE_SIZES = [25, 50, 100, 200] as const;

export function Pagination({
  page,
  pageCount,
  pageSize,
  total,
  onPage,
  onPageSize,
}: {
  page: number;
  pageCount: number;
  pageSize: number;
  total: number;
  onPage: (p: number) => void;
  onPageSize: (n: number) => void;
}) {
  if (total === 0) return null;
  const from = page * pageSize + 1;
  const to = Math.min(total, (page + 1) * pageSize);

  const btn = (label: string, disabled: boolean, action: () => void) => (
    <button
      type="button"
      disabled={disabled}
      onClick={action}
      style={{
        padding: "5px 10px",
        borderRadius: 6,
        border: `1px solid ${t.border}`,
        background: t.surface,
        color: disabled ? t.text3 : t.text2,
        cursor: disabled ? "default" : "pointer",
        fontSize: 12,
      }}
    >
      {label}
    </button>
  );

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 10,
        flexWrap: "wrap",
        marginBottom: 8,
        fontSize: 12,
        color: t.text3,
      }}
    >
      <span style={{ fontVariantNumeric: "tabular-nums" }}>
        {from}–{to} of {total.toLocaleString()}
      </span>
      <div style={{ display: "flex", gap: 4 }}>
        {btn("«", page <= 0, () => onPage(0))}
        {btn("‹", page <= 0, () => onPage(Math.max(0, page - 1)))}
        <span style={{ padding: "5px 8px", color: t.text2, fontVariantNumeric: "tabular-nums" }}>
          {page + 1} / {pageCount}
        </span>
        {btn("›", page >= pageCount - 1, () => onPage(Math.min(pageCount - 1, page + 1)))}
        {btn("»", page >= pageCount - 1, () => onPage(pageCount - 1))}
      </div>
      <label style={{ display: "flex", alignItems: "center", gap: 6, marginLeft: "auto" }}>
        <span>Per page</span>
        <select
          value={pageSize}
          onChange={(e) => onPageSize(Number(e.target.value))}
          style={{
            background: t.surface,
            color: t.text1,
            border: `1px solid ${t.border}`,
            borderRadius: 6,
            padding: "4px 8px",
            fontSize: 12,
          }}
        >
          {PAGE_SIZES.map((n) => (
            <option key={n} value={n}>
              {n}
            </option>
          ))}
        </select>
      </label>
    </div>
  );
}
