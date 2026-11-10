# 2. Running a case

## Prepare the case

Start from a ready-to-run case: mesh built, wave parameters set (`setWaveParameters`) and initial
wave field set (`setWaveField`). Copy it to Koa:

```bash
scp -r MyCase <uh-username>@koa.its.hawaii.edu:~/koa_scratch/openfoam/
```

If the case is in a zip file, note that the login nodes have no `unzip`. Use Python instead:

```bash
cd ~/koa_scratch/openfoam && python3 -m zipfile -e MyCase.zip .
```

If the mesh and wave field haven't been set up yet, create an empty file named `.init_waves` in the
case folder. The job then runs `setWaveParameters` and `setWaveField` (from `0.org`) before solving.
The mesh itself must already exist in `constant/polyMesh`.

### Recommended `controlDict` settings

```
writeFormat     binary;   // instead of ascii
writeInterval   2;        // full fields every 2 s (simulation time), so a stopped run can restart
```

- **Binary output** stores full double precision, while ascii rounds to `writePrecision` digits. It's
  also smaller, and much faster to read back when reconstructing. The solution itself doesn't change.
- **`writeInterval`** controls how often full restart data is written. Without it, a run that times
  out has to start again from t = 0.

You don't need to change `decomposeParDict`. The job script sets `numberOfSubdomains` to match the
number of cores.

## Submit

From inside the case folder, on the login node:

```bash
cd ~/koa_scratch/openfoam/MyCase && sbatch ../KOA_OpenFOAM/slurm/run_case.slurm
```

The job runs these steps:

1. **Wave init** (only if `.init_waves` exists): `setWaveParameters` + `setWaveField`
2. **decomposePar**: splits the mesh across the cores, written as one collated `processors<N>/` folder
3. **waveFoam**: the solver, in parallel
4. **reconstructPar**: one copy per core, each merging a slice of the time range

Each step writes a log in the case folder (`setWaves.log`, `decomposePar.log`, `waveFoam.log`,
`reconstructPar_*.log`). `stages.log` records when each step started.

### Cores, memory and time

Edit the `#SBATCH` lines in `run_case.slurm`, or override them on the command line:

```bash
sbatch -n 40 --mem=64G -t 12:00:00 ../KOA_OpenFOAM/slurm/run_case.slurm
```

- **Cores:** keep it to one node (the container's MPI runs within a single node). Koa `shared` nodes
  have 20, 24 or 40 cores. Smaller requests fit on more nodes, so they start sooner. 24 is a good
  default.
- **Cells per core:** aim for roughly 20,000–100,000 cells per core. Fewer than that, and the cores
  spend more time exchanging data than computing.
- **Memory:** about 2 GB per core is plenty for a few million cells.
- **Time:** the `shared` limit is 3 days. Ask for about 2× your expected run time. To estimate the
  run time, run the case for a few minutes and use `status.sh` (below).

## Monitor

```bash
squeue -u $USER                                        # is it running?
../KOA_OpenFOAM/scripts/status.sh                      # sim time, % done, est. remaining
tail -30 waveFoam.log                                  # solver output
```

Healthy signs in `waveFoam.log`:
- `Time =` keeps increasing
- `Courant Number ... max` stays below `maxCo` from `controlDict`
- `Phase-1 volume fraction` stays constant (mass is conserved)
- The run ends with `End` and `Finalising parallel run`

## If the job times out

Check where it stopped:

```bash
tail -5 stages.log
grep "^Time = " waveFoam.log | tail -1
```

- **Timed out during `reconstructPar`:** the simulation is complete. Finish only the merge:
  ```bash
  sbatch --export=ALL,RECON_ONLY=1 ../KOA_OpenFOAM/slurm/run_case.slurm
  ```
- **Timed out during `waveFoam`:** continue from the last full write (every `writeInterval` seconds):
  ```bash
  sbatch --export=ALL,RESTART=1 ../KOA_OpenFOAM/slurm/run_case.slurm
  ```
  This keeps the existing processor data, sets `startFrom latestTime`, runs the solver and then
  reconstructs. The previous `waveFoam.log` is kept with a timestamp suffix. Don't resubmit a normal
  run instead: its `decomposePar -force` would start over from t = 0.

## Where the results are

After the job finishes, the case folder contains:

| What | Where |
|---|---|
| Merged results | one folder per output time (e.g. `0.025`, `0.05`, ...) |
| Full restart data (`U`, `p_rgh`, `k`, `omega`, `nut`, ...) | every `writeInterval` |
| Decomposed data | `processors<N>/` (can be deleted once the merge is done) |

Next: [post-processing](4-post-processing.md).
