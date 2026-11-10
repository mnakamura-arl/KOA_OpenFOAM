# 2. Running a case

## Prepare the case

Start from a case that already runs on your workstation, with its mesh built and the wave field
set (the state after `buildmesh5.sh`). Copy it to Koa:

```bash
scp -r MyCase <uh-username>@koa.its.hawaii.edu:~/koa_scratch/openfoam/
```

If you only have a zip file, note that the login nodes have no `unzip`. Use Python instead:

```bash
cd ~/koa_scratch/openfoam && python3 -m zipfile -e MyCase.zip .
```

Then make two edits in `system/controlDict`:

```
writeFormat     binary;   // instead of ascii
writeInterval   2;        // write full fields every 2 s, so a killed run can restart
```

**Why binary:** it stores full double precision, while ascii with `writePrecision 7` rounds every
value. It's also far faster to reconstruct. We ran the same case both ways and compared every field
at all 1,601 output times. The only differences were the 7-digit ascii rounding (largest relative
difference: 5e-7).

You don't need to change `decomposeParDict`. The job script sets `numberOfSubdomains` to match the
number of cores.

## Submit

From inside the case folder, on the login node:

```bash
cd ~/koa_scratch/openfoam/MyCase && sbatch ../KOA_OpenFOAM/slurm/run_case.slurm
```

The job runs all of these steps:

1. **Wave init** (only if the case contains a `.init_waves` file): `setWaveParameters` + `setWaveField`
2. **decomposePar**: splits the mesh into 24 pieces, written as one collated `processors24/` folder
3. **waveFoam**: the solver, on 24 cores
4. **reconstructPar**: 24 copies in parallel, each merging a slice of the time range

Each step writes its own log in the case folder (`decomposePar.log`, `waveFoam.log`,
`reconstructPar_*.log`), and `stages.log` records when each step started.

### Changing cores, memory or time

Edit the `#SBATCH` lines in `run_case.slurm`, or override them on the command line:

```bash
sbatch -n 40 --mem=64G -t 12:00:00 ../KOA_OpenFOAM/slurm/run_case.slurm
```

- **Cores:** keep it to one node. Koa `shared` nodes have 20, 24 or 40 cores. 24 is a good default
  because many nodes can fit it, so jobs start sooner. 40 only fits on the less common 40-core nodes.
- **Memory:** about 2 GB per core is plenty for a 1–2 M-cell 2-D case.
- **Time:** the `shared` limit is 3 days. Ask for about 2× your expected run time.

## Monitor

```bash
squeue -u $USER                                        # is it running?
../KOA_OpenFOAM/scripts/status.sh                      # sim time, % done, est. remaining
tail -30 waveFoam.log                                  # solver output
```

Healthy signs in `waveFoam.log`:
- `Time =` keeps increasing
- `Courant Number ... max` stays below `maxCo` (0.4 in our case)
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
  This keeps the existing `processors24/` data, sets `startFrom latestTime`, runs the solver and then
  reconstructs. The previous `waveFoam.log` is kept with a timestamp suffix. Don't resubmit a normal
  run instead: its `decomposePar -force` would start over from t = 0.

## Where the results are

After the job finishes, the case folder contains:

| What | Where |
|---|---|
| Merged results, one folder per output time | `0.025`, `0.05`, ... `40` |
| Full restart data (`U`, `p_rgh`, `k`, `omega`, `nut`, ...) | every `writeInterval` (e.g. `2`, `4`, ... `40`) |
| Decomposed data | `processors24/` (can be deleted once the merge is done) |

Next: [post-processing](4-post-processing.md).

## Timing reference

T0.8 case: 1.16 M cells, 2-D, kOmegaSST with `multiphaseStabilizedTurbulence`, 40 s simulated,
`alpha.water` written every 0.025 s (1,601 output times).

| Setup | Solver | Reconstruct |
|---|---|---|
| Koa 24 cores, ascii + one file per core | 6.5 h | about 30 h (serial, then 24-way) |
| Koa 24 cores, binary + collated | 4.6 h | about 3.4 h (24-way parallel) |
| Workstation, 128 cores | about 2 h | n/a |

The two Koa runs landed on different node types, so part of the solver difference may be hardware.
