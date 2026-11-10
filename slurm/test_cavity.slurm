#!/bin/bash
#SBATCH -J of_test
#SBATCH -p sandbox
#SBATCH -N 1
#SBATCH -n 4
#SBATCH -t 00:15:00
#SBATCH --mem=4G
#SBATCH -o test_cavity-%j.out

# Smoke test for a new setup: checks the image, then runs the lid-driven cavity tutorial in serial and on 4 cores.
#     sbatch test_cavity.slurm
# Success = "TEST PASSED" at the end of test_cavity-<jobid>.out (takes about a minute).

set -eo pipefail
SIF=${SIF:-$HOME/koa_scratch/openfoam/waves2foam-2206.sif}
WORK=$HOME/koa_scratch/openfoam/test_cavity_$SLURM_JOB_ID

run() {
    apptainer exec "$SIF" bash -c "source /opt/foam-env.sh && $1"
}

echo "== image: $SIF"
run "command -v waveFoam setWaveParameters setWaveField"

mkdir -p "$WORK" && cd "$WORK"
run "cp -r \$FOAM_TUTORIALS/incompressible/icoFoam/cavity/cavity ."
cd cavity
printf 'FoamFile { version 2.0; format ascii; class dictionary; object decomposeParDict; }\nnumberOfSubdomains 4;\nmethod scotch;\n' > system/decomposeParDict

echo "== serial run"
run "blockMesh && icoFoam" > serial.log 2>&1 && tail -2 serial.log

echo "== parallel run (4 cores)"
run "decomposePar -force && mpirun -np 4 --mca btl self,vader icoFoam -parallel && reconstructPar -latestTime" > parallel.log 2>&1
grep -q "^End" parallel.log && tail -2 parallel.log

rm -rf "$WORK"
echo "TEST PASSED"
