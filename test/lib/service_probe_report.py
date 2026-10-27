#!/usr/bin/python3 -I
# ==============================================================================
# TITOLO:       service_probe_report.py
# AUTORE:       Elia Pinto
# DATA:         27 Ottobre 2026
# SCOPO:        Analizza i log di service_probe.sh (uno per nodo) e verifica la
#               durabilita' delle scritture confermate. Usato da
#               service_probe.yml.
#
# MODO "report" (--log NODO=FILE ...): per ogni nodo e tipo di operazione
# (R lettura, W scrittura) stampa operazioni riuscite/totali, disponibilita'
# %, interruzione massima (dal primo errore al successo seguente, o alla fine
# della sonda se il nodo non si e' ripreso) e latenza p50/p95/max delle
# operazioni riuscite. Scrive in --acked-out i DN delle scritture confermate
# (rc=0) e stampa una riga PROBE_JSON con i numeri per gli assert.
#
# MODO "durability" (--acked FILE --present NODO=FILE ...): per ogni nodo
# confronta i DN confermati con quelli presenti (un DN per riga, estratti da
# slapcat). Una scrittura confermata al client e assente su un nodo dopo la
# convergenza e' una perdita di dati. Le scritture andate in timeout (rc=124)
# non sono confermate: se presenti non sono un errore, si contano a parte.
#
# USCITA: 0 = ok; 1 = scritture confermate mancanti (durability); 2 = errore
# d'uso o log illeggibili.
#
# VERSIONE:     1.0
# CHANGELOG:
#   1.0 - 2026-10-27 - prima versione.
# ==============================================================================

import argparse
import json
import sys


def read_log(path):
    ops = {"R": [], "W": []}
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            parts = line.split()
            if not parts:
                continue
            if parts[0] not in ops or len(parts) < 5:
                raise ValueError(f"{path}:{lineno}: riga non valida: {line.strip()[:80]}")
            seq, start, rc, lat = (int(p) for p in parts[1:5])
            dn = parts[5] if len(parts) > 5 else ""
            ops[parts[0]].append((seq, start, rc, lat, dn))
    return ops


def percentile(values, pct):
    if not values:
        return 0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, round(pct / 100.0 * (len(ordered) - 1)))
    return ordered[idx]


def analyse(ops):
    """Statistiche di una sequenza di operazioni dello stesso tipo."""
    total = len(ops)
    ok = [o for o in ops if o[2] == 0]
    max_outage_ms = 0
    outage_open_at_end = False
    fail_start = None
    for seq, start, rc, lat, _dn in sorted(ops):
        if rc != 0:
            if fail_start is None:
                fail_start = start
        elif fail_start is not None:
            max_outage_ms = max(max_outage_ms, start - fail_start)
            fail_start = None
    if fail_start is not None:
        last = max(ops)
        max_outage_ms = max(max_outage_ms, last[1] + last[3] - fail_start)
        outage_open_at_end = True
    lats = [o[3] for o in ok]
    return {
        "total": total,
        "ok": len(ok),
        "availability_pct": round(100.0 * len(ok) / total, 2) if total else 0.0,
        "max_outage_s": round(max_outage_ms / 1000.0, 1),
        "outage_open_at_end": outage_open_at_end,
        "lat_p50_ms": percentile(lats, 50),
        "lat_p95_ms": percentile(lats, 95),
        "lat_max_ms": max(lats) if lats else 0,
    }


def report(args):
    summary = {}
    acked = []
    try:
        for item in args.log:
            node, sep, path = item.partition("=")
            if not sep:
                raise ValueError(f"--log non valido: {item}")
            ops = read_log(path)
            summary[node] = {kind: analyse(seq) for kind, seq in ops.items() if seq}
            acked += [o[4] for o in ops["W"] if o[2] == 0]
    except (OSError, ValueError) as exc:
        print(f"PROBE_ERROR: {exc}")
        return 2
    for node, kinds in summary.items():
        for kind, s in kinds.items():
            label = "lettura" if kind == "R" else "scrittura"
            still = " (ANCORA IN ERRORE a fine sonda)" if s["outage_open_at_end"] else ""
            print(f"PROBE {node} {label}: {s['ok']}/{s['total']} ok "
                  f"({s['availability_pct']}%), interruzione max {s['max_outage_s']}s{still}, "
                  f"latenza p50={s['lat_p50_ms']}ms p95={s['lat_p95_ms']}ms max={s['lat_max_ms']}ms")
    with open(args.acked_out, "w", encoding="utf-8") as fh:
        fh.write("".join(dn + "\n" for dn in acked))
    print(f"PROBE_ACKED_WRITES: {len(acked)}")
    print("PROBE_JSON " + json.dumps(summary, sort_keys=True))
    return 0


def read_dns(path):
    with open(path, encoding="utf-8") as fh:
        return {line.strip().lower() for line in fh if line.strip()}


def durability(args):
    try:
        acked = read_dns(args.acked)
        present = {}
        for item in args.present:
            node, sep, path = item.partition("=")
            if not sep:
                raise ValueError(f"--present non valido: {item}")
            present[node] = read_dns(path)
    except (OSError, ValueError) as exc:
        print(f"DURABILITY_ERROR: {exc}")
        return 2
    missing_any = False
    for node, dns in present.items():
        missing = sorted(acked - dns)
        unacked = len(dns - acked)
        if missing:
            missing_any = True
            print(f"DURABILITY_MISSING {node}: {len(missing)}/{len(acked)} scritture confermate "
                  f"assenti, es. {', '.join(missing[:5])}")
        else:
            print(f"DURABILITY {node}: {len(acked)}/{len(acked)} scritture confermate presenti"
                  f" (+{unacked} non confermate ma presenti)")
    if missing_any:
        print("DURABILITY_FAIL")
        return 1
    print(f"DURABILITY_OK: {len(acked)} scritture confermate presenti su {len(present)} nodi")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Analisi dei log della sonda di servizio")
    sub = parser.add_subparsers(dest="mode", required=True)
    rep = sub.add_parser("report")
    rep.add_argument("--log", action="append", required=True, metavar="NODO=FILE")
    rep.add_argument("--acked-out", required=True)
    dur = sub.add_parser("durability")
    dur.add_argument("--acked", required=True)
    dur.add_argument("--present", action="append", required=True, metavar="NODO=FILE")
    args = parser.parse_args()
    return report(args) if args.mode == "report" else durability(args)


if __name__ == "__main__":
    sys.exit(main())
