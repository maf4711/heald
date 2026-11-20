"use client";

import { useEffect, useState } from "react";

/**
 * Poll a JSON endpoint every `intervalMs` and return `json[key]` (or [] until
 * the first successful response). Failed fetches keep the last value and
 * retry on the next tick.
 */
export function usePolled<T>(url: string, key: string, intervalMs: number): T[] {
  const [items, setItems] = useState<T[]>([]);

  useEffect(() => {
    const load = async () => {
      try {
        const res = await fetch(url, { cache: "no-store" });
        if (res.ok) setItems((await res.json())[key] ?? []);
      } catch {
        /* retry on next tick */
      }
    };
    load();
    const interval = setInterval(load, intervalMs);
    return () => clearInterval(interval);
  }, [url, key, intervalMs]);

  return items;
}
