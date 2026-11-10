#!/bin/bash
# Progress of one or more running cases: simulated time, % done and estimated time left.
#
# Usage:
#     scripts/status.sh                 # the case in the current folder
#     scripts/status.sh CaseA CaseB     # specific case folders
#     scripts/status.sh $(cat cases.txt)  # every case in a sweep (run from the sweep folder)

[ $# -eq 0 ] && set -- .

printf "%-24s %10s %8s %10s %12s  %s\n" case sim_time done elapsed remaining stage
for c in "$@"; do
    log=$c/waveFoam.log
    # stages.log lines look like "== <date>  <stage>": keep the text after the last double space
    stage=$(tail -1 "$c/stages.log" 2>/dev/null | awk -F'  ' '{print $NF}')
    if [ ! -f "$log" ]; then
        printf "%-24s %10s %8s %10s %12s  %s\n" "$c" - - - - "${stage:-not started}"
        continue
    fi
    end=$(grep -E "^endTime" "$c/system/controlDict" | awk '{gsub(";","",$2); print $2}')
    t=$(grep "^Time = " "$log" | tail -1 | awk '{print $3}')
    clock=$(grep "ClockTime" "$log" | tail -1 | awk '{print $7}')
    awk -v c="$c" -v t="${t:-0}" -v e="$end" -v k="${clock:-0}" -v s="$stage" 'BEGIN{
        rem = (t > 0) ? k / t * (e - t) / 3600 : 0
        printf "%-24s %10.3f %7.0f%% %9.1fh %11.1fh  %s\n", c, t, 100 * t / e, k / 3600, rem, s }'
done
