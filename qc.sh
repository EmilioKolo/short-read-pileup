#!/usr/bin/env bash

set -euo pipefail

R1="$1"; R2="${2:-}"; OUTDIR="$3"

if command -v fastqc >/dev/null 2>&1; then
    fastqc -t 2 -o "$OUTDIR" "$R1" ${R2:+"$R2"} 2>/dev/null || true
fi

compute_avg_readlen(){
    local fq="$1"
    if [[ "$fq" == *.gz ]]; then
        zcat "$fq" | awk 'NR%4==2{sum+=length($0);cnt++} END{if(cnt>0) print sum/cnt; else print 0}'
    else
        awk 'NR%4==2{sum+=length($0);cnt++} END{if(cnt>0) print sum/cnt; else print 0}' "$fq"
    fi
}

if [[ -f "$R1" ]]; then echo "avg_readlen_R1: $(compute_avg_readlen "$R1")" > "$OUTDIR"/avg_readlen.txt; fi
if [[ -n "$R2" && -f "$R2" ]]; then echo "avg_readlen_R2: $(compute_avg_readlen "$R2")" >> "$OUTDIR"/avg_readlen.txt; fi
