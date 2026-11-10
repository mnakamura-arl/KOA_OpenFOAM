# OpenFOAM + waves2Foam on UH Koa

Run [waves2Foam](https://openfoamwiki.net/index.php/Contrib/waves2Foam) wave-flume simulations on the
University of Hawaiʻi **Koa** HPC cluster, using a ready-made Apptainer container.
There's nothing to compile.

- **Container:** OpenFOAM v2206 (ESI/openfoam.com) + waves2Foam r2157, published at
  [`ghcr.io/mnakamura-arl/waves2foam`](https://github.com/users/mnakamura-arl/packages/container/package/waves2foam)
- **Tested with:** a 2-D, 1.16 M-cell dual-plate breakwater case (`T0.8`). The results match
  the lab workstation's, and the incident wave amplitude is within 0.1% of the target.

## Quick start

```bash
# 1. On a Koa compute node (apptainer is not installed on the login nodes)
srun -p sandbox -c 2 --mem=4G -t 0:30:00 --pty /bin/bash
mkdir -p ~/koa_scratch/openfoam && cd ~/koa_scratch/openfoam
apptainer pull waves2foam-2206.sif oras://ghcr.io/mnakamura-arl/waves2foam:v2206-r2157
git clone <this-repo-url> KOA_OpenFOAM        # or copy this folder over with scp
exit

# 2. Back on the login node: smoke test (about 1 minute)
cd ~/koa_scratch/openfoam && sbatch KOA_OpenFOAM/slurm/test_cavity.slurm
#    -> "TEST PASSED" at the end of test_cavity-<jobid>.out

# 3. Run your case (set "writeFormat binary;" in system/controlDict first)
cd ~/koa_scratch/openfoam/MyCase && sbatch ../KOA_OpenFOAM/slurm/run_case.slurm
```

## Documentation

| | |
|---|---|
| [1. Getting started](docs/1-getting-started.md) | Koa account, logging in, storage, getting the container, smoke test |
| [2. Running a case](docs/2-running-a-case.md) | Preparing a case, submitting, monitoring, restarting, timing |
| [3. Multiple runs](docs/3-multiple-runs.md) | Parameter sweeps with job arrays, dependent jobs |
| [4. Post-processing](docs/4-post-processing.md) | Copying results back, ParaView, wave-gauge analysis, videos |
| [5. Building the image](docs/5-building-the-image.md) | Rebuilding or updating the container, publishing it |
| [Troubleshooting](docs/troubleshooting.md) | Problems we hit and how to fix them |

## What's in this repo

```
slurm/run_case.slurm          one case end to end: wave init -> decompose -> solve -> reconstruct
                              (also runs a whole sweep as a job array)
slurm/test_cavity.slurm       1-minute check that the container and MPI work
scripts/make_sweep.sh         make a set of cases from a template (vary wave period/height)
scripts/status.sh             progress and time remaining for running cases
scripts/compare_runs.py       compare two runs field by field (e.g. to verify a settings change)
postprocessing/               headless ParaView setup, video rendering, wave-gauge analysis (plot_ws3.py)
container/                    Apptainer recipe and Koa build job for the image
```

## Typical timing (T0.8 case, 1.16 M cells, 40 s simulated, 24 cores on Koa)

| Step | Time |
|---|---|
| Solver (waveFoam) | 4.6 h |
| Reconstruct (24-way parallel) | about 3.5 h |
| Lab workstation, 128 cores, solver only | about 2 h |

Koa is slower per run than the 128-core workstation, but it can run many cases **at the same time**,
so it's best for sweeps. See [3. Multiple runs](docs/3-multiple-runs.md).
