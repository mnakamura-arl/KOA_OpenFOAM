# 3. Multiple runs

Koa's advantage over a single big workstation is running many cases at the same time. Ten 24-core
jobs running side by side finish in about the time one job takes.

| | 10 cases |
|---|---|
| 128-core workstation, one after another | about 20 h |
| Koa, 10 × 24-core jobs at once (if the queue allows) | about 8 h |

## Option A: a parameter sweep with `make_sweep.sh` + a job array

`make_sweep.sh` copies a template case once per wave period and writes the list of cases to
`cases.txt`:

```bash
cd ~/koa_scratch/openfoam
KOA_OpenFOAM/scripts/make_sweep.sh T0.8_input sweep_H9mm 0.8 1.0 1.2 1.4 1.6
```

For each period it creates `sweep_H9mm/T<period>/` with:
- `period` set in `constant/waveProperties.input`
- `writeFormat binary;` in `system/controlDict`
- the same mesh as the template (no rebuild)
- a `.init_waves` marker, so the job reruns `setWaveParameters` + `setWaveField` before solving
- no old results or logs

To change the wave height for the whole sweep too, set `HEIGHT`:

```bash
HEIGHT=0.012 KOA_OpenFOAM/scripts/make_sweep.sh T0.8_input sweep_H12mm 0.8 1.0 1.2
```

Then submit all the cases as one **job array**:

```bash
cd sweep_H9mm
sbatch --array=0-4 ../KOA_OpenFOAM/slurm/run_case.slurm       # 5 cases, all at once
sbatch --array=0-4%2 ../KOA_OpenFOAM/slurm/run_case.slurm     # 5 cases, at most 2 running at a time
```

Array task `i` runs the case on line `i+1` of `cases.txt`. Watch them all:

```bash
squeue -u $USER                                  # array tasks show as <jobid>_<index>
../KOA_OpenFOAM/scripts/status.sh $(cat cases.txt)
```

**Before a sweep, check:**
- **Relaxation zones:** the inlet (x = 0–4 m) and outlet (16–20 m) zones should be at least about one
  wavelength long. Longer periods mean longer waves. In 0.625 m of water:

  | T (s) | 0.8 | 1.0 | 1.2 | 1.4 | 1.6 |
  |---|---|---|---|---|---|
  | L (m) | 1.00 | 1.54 | 2.14 | 2.73 | 3.31 |
- **Mesh resolution:** shorter or steeper waves need more cells per wavelength and per wave height.
- **`Tsoft`** (ramp-up time) in `waveProperties.input` stays as in the template. Scale it with the
  period if you want the same number of ramp-up waves.
- **Analysis window:** `plot_ws3.py` analyses 4 periods starting at t = 30 s, so `endTime` must be
  at least 30 + 4T.

To vary something other than period or height, edit the generated cases before submitting (for
example with `sed` or `foamDictionary`), or copy `make_sweep.sh` and change the `sed` lines.

## Option B: your own list of cases

A job array works for any set of ready-to-run case folders. Put their paths in a text file, one per
line, relative to the folder you submit from:

```bash
cd ~/koa_scratch/openfoam
printf "CaseA\nCaseB\nCaseC\n" > my_cases.txt
sbatch --array=0-2 --export=ALL,CASE_LIST=my_cases.txt KOA_OpenFOAM/slurm/run_case.slurm
```

## Option C: separate jobs

Submitting each case on its own also works:

```bash
for c in CaseA CaseB CaseC; do (cd $c && sbatch ../KOA_OpenFOAM/slurm/run_case.slurm); done
```

## Chaining jobs with dependencies

To start a job only after another one ends (whether it finished or failed), use `afterany`. To
start only after a success, use `afterok`.

```bash
sbatch --dependency=afterany:<jobid> --export=ALL,RECON_ONLY=1 ../KOA_OpenFOAM/slurm/run_case.slurm
```

For example, queue a "finish the merge" job right after submitting a long run. If the run times out
during reconstruction, the follow-up job finishes the merge. If it didn't time out, the follow-up
finds nothing left to merge and exits quickly.

## Being a good neighbour

- **Use `%N` on large arrays** to limit how many run at once (e.g. `--array=0-49%10`).
- **Delete `processors24/`** after a successful merge. It's a full second copy of the results.
- **`kill-shared`** has many idle cores but jobs can be killed. Only use it with `writeInterval` set,
  so a killed run can restart.
