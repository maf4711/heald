#!/usr/bin/env python3
"""Render engine for heald-top. Reads JSON from temp files, outputs ANSI."""

import json, sys, os
from datetime import datetime, timezone

cols = int(sys.argv[1]) if len(sys.argv) > 1 else 120
rows = int(sys.argv[2]) if len(sys.argv) > 2 else 40
interval = sys.argv[3] if len(sys.argv) > 3 else "5"

B, D, R, G, Y, RD, C = (
    "\033[1m",
    "\033[2m",
    "\033[0m",
    "\033[32m",
    "\033[33m",
    "\033[31m",
    "\033[36m",
)
BG = "\033[48;5;234m"
SEP = "\u2500"
DASH = "\u2014"
BLOCK = "\u2588"
SHADE = "\u2591"

try:
    with open("/tmp/.heald-top-m.json") as f:
        machines = json.load(f).get("machines", [])
except Exception:
    machines = []

try:
    with open("/tmp/.heald-top-e.json") as f:
        events = json.load(f).get("events", [])
except Exception:
    events = []

now = datetime.now(timezone.utc)


def ago(iso):
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        s = (now - dt).total_seconds()
        if s < 60:
            return f"{int(s)}s"
        if s < 3600:
            return f"{int(s // 60)}m"
        if s < 86400:
            return f"{int(s // 3600)}h"
        return f"{int(s // 86400)}d"
    except Exception:
        return "?"


def cpct(v):
    if v >= 90:
        return f"{RD}{v:5.1f}%{R}"
    if v >= 80:
        return f"{Y}{v:5.1f}%{R}"
    return f"{G}{v:5.1f}%{R}"


def spct(p):
    if p >= 99.9:
        return f"{G}{p:5.1f}%{R}"
    if p >= 90:
        return f"{Y}{p:5.1f}%{R}"
    return f"{RD}{p:5.1f}%{R}"


def bar(p, w=12):
    filled = int(p / 100 * w)
    empty = w - filled
    cl = G if p >= 99.9 else (Y if p >= 90 else RD)
    return f"{cl}{BLOCK * filled}{SHADE * empty}{R}"


# --- Fleet stats ---
n = len(machines)
online = 0
for m in machines:
    try:
        dt = datetime.fromisoformat(
            m.get("lastSeen", "2000-01-01T00:00:00Z").replace("Z", "+00:00")
        )
        if (now - dt).total_seconds() < 600:
            online += 1
    except Exception:
        pass

stale = n - online
avg_cpu = sum(m.get("cpu", {}).get("overall", 0) for m in machines) / max(n, 1) * 100
ic_ok = sum(1 for m in machines if m.get("icloud", {}).get("syncPercent", 100) >= 99.9)
ic_bad = sum(
    1
    for m in machines
    if m.get("icloud") and m["icloud"].get("syncPercent", 100) < 99.9
)
cloud_total = sum(m.get("icloud", {}).get("cloudFiles", 0) for m in machines)
conflicts = sum(m.get("icloud", {}).get("conflicts", 0) for m in machines)
bird_down = sum(
    1 for m in machines if m.get("icloud") and not m["icloud"].get("birdRunning", True)
)

o = []
ts = now.strftime("%H:%M:%S")

# Clear screen + header
o.append("\033[H\033[J")
o.append(
    f"{B}heald-top{R} {DASH} {ts} {DASH} {n} machines {DASH} refresh {interval}s\n"
)

# Fleet bar
o.append(f"{B}Fleet:{R}  {G}{online}{R} online")
if stale:
    o.append(f"  {RD}{stale} stale{R}")
o.append(f"  CPU avg {cpct(avg_cpu)}")
o.append(f"  iCloud {G}{ic_ok}{R} ok")
if ic_bad:
    o.append(f" {Y}{ic_bad} sync{R}")
if cloud_total:
    o.append(f" {RD}{cloud_total} cloud{R}")
if conflicts:
    o.append(f" {RD}{conflicts} conflicts{R}")
if bird_down:
    o.append(f" {RD}{bird_down} bird down{R}")
o.append("\n")

# Separator
o.append(f"{D}{SEP * min(cols, 140)}{R}\n")

# Table header
hdr = (
    f"{'HOSTNAME':<20} {'AGO':>4} {'CPU':>6} {'RAM':>8} {'SWAP':>6} "
    f"{'DISK':>12} {'SYNC':>6} {'BAR':<14} {'LOCAL':>7} {'CLOUD':>6} {'BIRD':>5}"
)
o.append(f"{BG}{B}{hdr[:cols]}{R}\n")


# Sort: problems first, then stale, then name
def sort_key(m):
    ic = m.get("icloud", {})
    problems = 0
    if ic.get("cloudFiles", 0) > 0:
        problems += 1
    if ic.get("conflicts", 0) > 0:
        problems += 1
    if not ic.get("birdRunning", True):
        problems += 1
    if ic.get("syncPercent", 100) < 90:
        problems += 1
    try:
        dt = datetime.fromisoformat(
            m.get("lastSeen", "2000-01-01T00:00:00Z").replace("Z", "+00:00")
        )
        is_stale = 0 if (now - dt).total_seconds() < 600 else 1
    except Exception:
        is_stale = 1
    return (-problems, is_stale, m.get("hostname", ""))


machines.sort(key=sort_key)

ev_rows = min(len(events), 6)
avail = rows - 7 - ev_rows

for m in machines[: max(avail, 3)]:
    hostname = m.get("hostname", "?")[:19]
    last_seen = ago(m.get("lastSeen", ""))
    cpu_pct = m.get("cpu", {}).get("overall", 0) * 100
    ram_gb = m.get("ram", {}).get("usedGB", 0)
    swap_mb = m.get("ram", {}).get("swapUsedMB", 0)

    # Disk
    vols = m.get("disk", {}).get("volumes", [])
    root_vol = next((v for v in vols if v.get("mountPoint") == "/"), None)
    if root_vol:
        total_gb = root_vol.get("totalGB", 0)
        free_gb = root_vol.get("freeGB", 0)
        disk_str = f"{total_gb - free_gb:.0f}/{total_gb:.0f}GB"
    else:
        disk_str = DASH

    # iCloud
    ic = m.get("icloud", {})
    sync_pct = ic.get("syncPercent", -1)
    local_files = ic.get("localFiles", 0)
    cloud_files = ic.get("cloudFiles", 0)
    bird_ok = ic.get("birdRunning", True)

    # Stale?
    is_stale = last_seen.endswith("h") or last_seen.endswith("d")

    # Format hostname
    if is_stale:
        h_fmt = f"{D}{hostname:<20}{R}"
    else:
        h_fmt = f"{C}{hostname:<20}{R}"

    # Sync
    if sync_pct >= 0:
        sync_fmt = spct(sync_pct)
        bar_fmt = bar(sync_pct)
    else:
        sync_fmt = f"{DASH:>6}"
        bar_fmt = " " * 14

    # Cloud files
    if cloud_files > 0:
        cloud_fmt = f"{RD}{cloud_files:>6}{R}"
    else:
        cloud_fmt = f"{'0':>6}"

    # Bird
    if bird_ok:
        bird_fmt = f"{G}{'ok':>5}{R}"
    else:
        bird_fmt = f"{RD}{'DOWN':>5}{R}"

    # Swap
    if swap_mb > 500:
        swap_fmt = f"{RD}{swap_mb:5.0f}M{R}"
    else:
        swap_fmt = f"{swap_mb:5.0f}M"

    # Local
    if local_files > 0:
        local_fmt = f"{local_files:>7}"
    else:
        local_fmt = f"{DASH:>7}"

    row = (
        f"{h_fmt} {last_seen:>4} {cpct(cpu_pct)} {ram_gb:7.1f}G {swap_fmt} "
        f"{disk_str:>12} {sync_fmt} {bar_fmt} {local_fmt} {cloud_fmt} {bird_fmt}"
    )
    o.append(row + "\n")

if n > avail > 0:
    o.append(f"{D}  ... +{n - avail} more{R}\n")

# --- Events ---
if events:
    o.append(f"\n{D}{SEP * min(cols, 140)}{R}\n")
    o.append(f"{B}Recent:{R}\n")
    type_colors = {
        "process_killed": RD,
        "icloud_sync_degraded": Y,
        "icloud_daemon_down": RD,
        "daemon_started": G,
        "dns_flushed": C,
        "crash_detected": RD,
        "spotlight_fix": C,
        "retention_purge": D,
    }
    for ev in events[:ev_rows]:
        t = ev.get("type", "")
        color = type_colors.get(t, D)
        ev_ts = ev.get("timestamp", "")[:19].replace("T", " ")
        summary = ev.get("summary", "")[: cols - 35]
        machine_id = ev.get("machineId", "")[:10]
        o.append(f"  {D}{ev_ts}{R} {color}{summary}{R} {D}{machine_id}{R}\n")

# Footer
o.append(f"\n{D}q:quit  r:refresh  heald.sh  interval:{interval}s{R}")

sys.stdout.write("".join(o))
sys.stdout.flush()
