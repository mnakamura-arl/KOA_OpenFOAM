#!/bin/bash
#SBATCH --job-name=build_w2f
#SBATCH --partition=sandbox
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=build_image-%j.out

# Build the waves2Foam (OpenFOAM v2206) Apptainer image on Koa. Only needed to change the image;
# normally just pull the published one (see docs/5-building-the-image.md).
#
# Apptainer's cache and temp folders go on node-local /tmp: unpacking the image on Lustre takes
# hours, while on /tmp it takes under a minute. The .sif is built
# on /tmp and copied to scratch at the end, so Lustre only sees one large sequential write.
#
# Submit from the folder holding waves2foam-2206.def:   sbatch build_image.slurm

set -euo pipefail

WORKDIR=$SLURM_SUBMIT_DIR
DEF=waves2foam-2206.def
SIF=waves2foam-2206.sif

export APPTAINER_CACHEDIR=/tmp/$USER-apptainer-cache
export APPTAINER_TMPDIR=/tmp/$USER-apptainer
LOCAL_SIF=/tmp/$USER-$SIF

cleanup() { rm -rf "$LOCAL_SIF" "$APPTAINER_TMPDIR" "$APPTAINER_CACHEDIR"; }
trap cleanup EXIT   # /tmp is RAM-backed: always free it, even if the build fails or times out

cd "$WORKDIR"
mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR"

echo "== $(date)  job $SLURM_JOB_ID on $(hostname), $SLURM_CPUS_PER_TASK CPUs"
df -h /tmp
apptainer --version

echo "== $(date)  building $DEF"
apptainer build --force "$LOCAL_SIF" "$DEF" \
    || apptainer build --fakeroot --force "$LOCAL_SIF" "$DEF"

echo "== $(date)  copying image to $WORKDIR/$SIF"
cp "$LOCAL_SIF" "$WORKDIR/$SIF"
ls -lh "$WORKDIR/$SIF"

apptainer exec "$WORKDIR/$SIF" bash -c "source /opt/foam-env.sh && command -v waveFoam setWaveField"
echo "== $(date)  done"
