# 1. Getting started

## Account and login

You need a Koa account. Request one through UH ITS Cyberinfrastructure if you don't have one.

```bash
ssh <uh-username>@koa.its.hawaii.edu
```

You'll be asked for your UH password and a Duo approval. The Koa **Open OnDemand** web portal also
gives you a shell in the browser.

## Where things run

| Node | What it's for | Notes |
|---|---|---|
| Login node (`login-0101`, ...) | Editing files, submitting jobs, light commands | **No `apptainer` here.** Don't run simulations here. |
| Compute node (`cn-...`, `vn-...`) | Everything that uses the container | Get one with `srun` (interactive) or `sbatch` (batch job) |

For an interactive compute node, which is useful for testing:

```bash
srun -p sandbox -c 2 --mem=4G -t 0:30:00 --pty /bin/bash     # sandbox: max 4 h, starts quickly
exit                                                          # back to the login node when done
```

## Storage

| Location | Use |
|---|---|
| `~` (home) | Small quota. Keep scripts here, not results. |
| `~/koa_scratch` | Large and fast. **Run all cases here.** Files are purged after a period of inactivity, so copy results off. |
| Group storage (e.g. `~/nslab_storage_group`) | Shared with your group. Good for a shared copy of the container. |

Everything in these docs assumes the working folder is `~/koa_scratch/openfoam`.

## Get the container

On a compute node, run:

```bash
mkdir -p ~/koa_scratch/openfoam && cd ~/koa_scratch/openfoam
apptainer pull waves2foam-2206.sif oras://ghcr.io/mnakamura-arl/waves2foam:v2206-r2157
```

This is a 374 MB download and takes a minute or two. The image is public, so you don't need a
GitHub login.

Quick check, still on the compute node:

```bash
apptainer exec waves2foam-2206.sif bash -c "source /opt/foam-env.sh && command -v waveFoam"
# -> /opt/waves2Foam/platform/bin/waveFoam
```

Every OpenFOAM command runs inside the container like this:

```bash
apptainer exec waves2foam-2206.sif bash -c "source /opt/foam-env.sh && <openfoam commands>"
```

`/opt/foam-env.sh` loads OpenFOAM v2206 and puts the waves2Foam tools on the path (`waveFoam`,
`setWaveParameters`, `setWaveField`, `waveGaugesNProbes`, ...).

## Get these scripts onto Koa

Either `git clone` this repository into `~/koa_scratch/openfoam/KOA_OpenFOAM`, or copy it from your
own machine:

```bash
scp -r KOA_OpenFOAM <uh-username>@koa.its.hawaii.edu:~/koa_scratch/openfoam/
```

## Smoke test

From the login node, run:

```bash
cd ~/koa_scratch/openfoam && sbatch KOA_OpenFOAM/slurm/test_cavity.slurm
squeue -u $USER                       # wait until it's gone (about 1 minute once it starts)
tail -3 test_cavity-*.out             # -> TEST PASSED
```

This runs the OpenFOAM cavity tutorial in serial and on 4 cores with MPI. If it passes, you're ready
to [run a case](2-running-a-case.md).

## Useful Slurm commands

| Command | What it shows |
|---|---|
| `squeue -u $USER` | Your jobs. `PD` = waiting, `R` = running |
| `squeue -u $USER --start` | Estimated start time of waiting jobs |
| `sacct -X --format=JobID,JobName,State,Elapsed` | Finished jobs and how they ended |
| `scancel <jobid>` | Cancel a job |
| `sinfo -o "%15P %20C %10l"` | Partitions: CPUs allocated/idle/other/total, and time limits |

The partitions we use:

| Partition | Time limit | Notes |
|---|---|---|
| `sandbox` | 4 h | Testing and builds; starts quickly |
| `shared` | 3 days | Normal runs. Nodes have 20, 24 or 40 cores |
| `kill-shared` | 3 days | Many idle cores, but jobs **can be killed** by the node owners |
