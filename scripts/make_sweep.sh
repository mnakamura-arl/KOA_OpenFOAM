#!/bin/bash
# Make a set of cases from one template case, varying the inlet wave period (and optionally height),
# and write cases.txt for an array job.
#
# Usage:
#     scripts/make_sweep.sh <template_case> <sweep_dir> <period> [period ...]
#     HEIGHT=0.012 scripts/make_sweep.sh <template_case> <sweep_dir> 0.8 1.0 1.2
#
# Example:
#     scripts/make_sweep.sh T0.8_input sweep_H9mm 0.8 1.0 1.2 1.4
#     cd sweep_H9mm && sbatch --array=0-3 ../KOA_OpenFOAM/slurm/run_case.slurm
#
# Each new case is named T<period> and gets:
#   - period (and height, if HEIGHT is set) changed in constant/waveProperties.input
#   - writeFormat set to binary in system/controlDict
#   - a .init_waves marker, so run_case.slurm regenerates waveProperties and the initial wave field
#   - no old results, logs, or processor folders
# The mesh is reused as-is. Check that the relaxation zones are still long enough for the
# longest wavelength (a common rule of thumb is at least one wavelength).

set -euo pipefail

if [ $# -lt 3 ]; then
    sed -n '2,20p' "$0"
    exit 1
fi

TEMPLATE=$1
SWEEP=$2
shift 2

[ -f "$TEMPLATE/constant/waveProperties.input" ] || { echo "No constant/waveProperties.input in $TEMPLATE"; exit 1; }
[ -d "$TEMPLATE/0.org" ] || { echo "No 0.org in $TEMPLATE (needed to rebuild the initial wave field)"; exit 1; }

mkdir -p "$SWEEP"
: > "$SWEEP/cases.txt"

for T in "$@"; do
    name=T$T
    dest=$SWEEP/$name
    echo "== $dest"
    mkdir -p "$dest"
    # Copy only what a run needs: no time folders, processor data, logs or post-processing output
    cp -r "$TEMPLATE/constant" "$TEMPLATE/system" "$TEMPLATE/0.org" "$dest/"
    rm -rf "$dest"/constant/polyMesh/sets
    for f in "$TEMPLATE"/*.foam "$TEMPLATE"/waveGaugesNProbes; do
        [ -e "$f" ] && cp -r "$f" "$dest/"
    done

    wp=$dest/constant/waveProperties.input
    # period / height appear once, inside inletCoeffs
    sed -i -E "s/^([[:space:]]*period[[:space:]]+)[^;]+;/\1$T;/" "$wp"
    if [ -n "${HEIGHT:-}" ]; then
        sed -i -E "s/^([[:space:]]*height[[:space:]]+)[^;]+;/\1$HEIGHT;/" "$wp"
    fi
    grep -E "^[[:space:]]*(period|height)[[:space:]]" "$wp" | sed 's/^/     /'

    # binary output: smaller, exact, and much faster to reconstruct (verified identical to ascii results)
    sed -i -E "s/^writeFormat[[:space:]]+[a-z]+;/writeFormat     binary;/" "$dest/system/controlDict"

    touch "$dest/.init_waves"
    echo "$name" >> "$SWEEP/cases.txt"
done

n=$(wc -l < "$SWEEP/cases.txt")
echo
echo "Made $n cases in $SWEEP (listed in $SWEEP/cases.txt). Submit with:"
echo "    cd $SWEEP && sbatch --array=0-$((n - 1)) <path>/slurm/run_case.slurm"
