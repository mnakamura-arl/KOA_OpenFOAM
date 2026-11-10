#!/bin/bash
#SBATCH -J waveFoam
#SBATCH -p shared
#SBATCH -N 1
#SBATCH -n 24
#SBATCH -t 24:00:00
#SBATCH --mem=48G
#SBATCH -o slurm-%j.out

# Run one waves2Foam case end to end: (optional wave init) -> decomposePar -> waveFoam -> parallel reconstructPar.
#
# Single case (submit from inside the case folder, or pass the case path):
#     sbatch run_case.slurm
#     sbatch run_case.slurm path/to/case
#
# Many cases as a job array (one case per line in cases.txt, relative to where you submit):
#     sbatch --array=0-9%5 run_case.slurm           # 10 cases, at most 5 running at once
#
# Options (set with --export=ALL,NAME=value):
#     SIF=/path/to/image.sif   container image (default: ~/koa_scratch/openfoam/waves2foam-2206.sif)
#     CASE_LIST=file           case list for array jobs (default: cases.txt)
#     RECON_ONLY=1             skip the solver and only finish reconstructPar (after a timeout)
#     RESTART=1                continue an unfinished solver run from its latest full write
#                              (keeps processors24/, sets startFrom latestTime)
#
# If the case folder contains a file named .init_waves, the job first regenerates the wave
# parameters and the initial wave field (setWaveParameters + setWaveField) and then deletes the file.
# scripts/make_sweep.sh creates that file for every case it makes.

set -eo pipefail

SIF=${SIF:-$HOME/koa_scratch/openfoam/waves2foam-2206.sif}
FH="-fileHandler collated"

# Which case?
if [ -n "$1" ]; then
    CASE=$1
elif [ -n "$SLURM_ARRAY_TASK_ID" ]; then
    CASE=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" "$SLURM_SUBMIT_DIR/${CASE_LIST:-cases.txt}")
    [ -n "$CASE" ] || { echo "No line $((SLURM_ARRAY_TASK_ID + 1)) in ${CASE_LIST:-cases.txt}"; exit 1; }
else
    CASE=$SLURM_SUBMIT_DIR
fi
cd "$SLURM_SUBMIT_DIR" && cd "$CASE"
echo "== $(date)  case $(pwd) on $(hostname), $SLURM_NTASKS cores" | tee -a stages.log

[ -f "$SIF" ] || { echo "Container image not found: $SIF"; exit 1; }
[ -f system/controlDict ] || { echo "Not an OpenFOAM case (no system/controlDict): $(pwd)"; exit 1; }

run() {
    apptainer exec "$SIF" bash -c "source /opt/foam-env.sh && $1"
}

if [ -n "$RESTART" ]; then
    echo "== $(date)  waveFoam (restart from latest time)" | tee -a stages.log
    run "foamDictionary system/controlDict -entry startFrom -set latestTime > /dev/null"
    mv -f waveFoam.log "waveFoam.log.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    run "mpirun -np $SLURM_NTASKS --mca btl self,vader waveFoam -parallel $FH" &> waveFoam.log
elif [ -z "$RECON_ONLY" ]; then
    if [ -f .init_waves ]; then
        echo "== $(date)  setWaveParameters + setWaveField" | tee -a stages.log
        rm -rf 0 && cp -r 0.org 0
        run "setWaveParameters && setWaveField" &> setWaves.log
        rm -f .init_waves
    fi

    echo "== $(date)  decomposePar" | tee -a stages.log
    run "foamDictionary system/decomposeParDict -entry numberOfSubdomains -set $SLURM_NTASKS && decomposePar -force $FH" &> decomposePar.log

    echo "== $(date)  waveFoam" | tee -a stages.log
    run "mpirun -np $SLURM_NTASKS --mca btl self,vader waveFoam -parallel $FH" &> waveFoam.log
fi

# Reconstruct in parallel: split 0..endTime evenly across the cores; -newTimes skips times already done
echo "== $(date)  reconstructPar" | tee -a stages.log
END=$(run "foamDictionary system/controlDict -entry endTime -value" | tail -1)
for i in $(seq 0 $((SLURM_NTASKS - 1))); do
    r=$(awk -v i=$i -v n=$SLURM_NTASKS -v e=$END 'BEGIN{printf "%g:%g", i*e/n, (i+1)*e/n}')
    run "reconstructPar $FH -newTimes -time $r" &> reconstructPar_$i.log &
done
wait

echo "== $(date)  done" | tee -a stages.log
