# 3. Multiple runs

Each job runs on one node, but you can run many jobs at once. For a set of cases, submit them
together rather than one after another.

## Option A: a parameter sweep with `make_sweep.sh` + a job array

`make_sweep.sh` copies a template case once per wave period and writes the list of cases to
`cases.txt`:

```bash
cd ~/koa_scratch/openfoam
KOA_OpenFOAM/scripts/make_sweep.sh MyTemplate sweep_A 0.8 1.0 1.2 1.4 1.6
```

For each period, it creates `sweep_A/T<period>/` with:
- `period` set in `constant/waveProperties.input`
- `writeFormat binary;` in `system/controlDict`
- the same mesh as the template (no rebuild)
- a `.init_waves` marker, so the job reruns `setWaveParameters` + `setWaveField` before solving
- no old results or logs

The template needs `constant/` (with the mesh and `waveProperties.input`), `system/` and `0.org/`.

To set the wave height for the whole sweep too, set `HEIGHT` (in metres):

```bash
HEIGHT=0.012 KOA_OpenFOAM/scripts/make_sweep.sh MyTemplate sweep_B 0.8 1.0 1.2
```

Then submit all the cases as one **job array**:

```bash
cd sweep_A
sbatch --array=0-4 ../KOA_OpenFOAM/slurm/run_case.slurm       # 5 cases, all at once
sbatch --array=0-4%2 ../KOA_OpenFOAM/slurm/run_case.slurm     # 5 cases, at most 2 running at a time
```

Array task `i` runs the case on line `i+1` of `cases.txt`. To watch them all:

```bash
squeue -u $USER                                  # array tasks show as <jobid>_<index>
../KOA_OpenFOAM/scripts/status.sh $(cat cases.txt)
```

**Before a sweep, check:**
- **Relaxation zones:** the inlet and outlet relaxation zones should be at least about one wavelength
  long. Longer periods give longer waves. Solve the dispersion relation for the longest period in
  your sweep. `plot_ws3.py` prints L/4 for each case, for reference.
- **Mesh resolution:** shorter or steeper waves need more cells per wavelength and per wave height.
- **`Tsoft`** (ramp-up time) in `waveProperties.input` is copied from the template. Scale it with the
  period if you want the same number of ramp-up waves.
- **`endTime`** must be long enough for the waves to reach steady state, plus your analysis window,
  at the longest period.

To vary something other than period or height, edit the generated cases before submitting (for
example with `sed` or `foamDictionary`), or copy `make_sweep.sh` and change its `sed` lines.

## Option B: your own list of cases

A job array works for any set of ready-to-run case folders. Put their paths in a text file, one per
line, relative to the folder you submit from:

```bash
cd ~/koa_scratch/openfoam
printf "CaseA\nCaseB\nCaseC\n" > my_cases.txt
sbatch --array=0-2 --export=ALL,CASE_LIST=my_cases.txt KOA_OpenFOAM/slurm/run_case.slurm
```

## Option C: separate jobs

You can also submit each case on its own:

```bash
for c in CaseA CaseB CaseC; do (cd $c && sbatch ../KOA_OpenFOAM/slurm/run_case.slurm); done
```

## Chaining jobs with dependencies

To start a job only after another one ends (whether it finished or failed), use `afterany`. To start
only after a success, use `afterok`.

```bash
sbatch --dependency=afterany:<jobid> --export=ALL,RECON_ONLY=1 ../KOA_OpenFOAM/slurm/run_case.slurm
```

For example, queue a "finish the merge" job right after submitting a long run. If the run times out
during reconstruction, the follow-up job finishes the merge. If it didn't time out, the follow-up
finds nothing left to merge and exits quickly.

## Being a good neighbour

- **Use `%N` on large arrays** to limit how many run at once (e.g. `--array=0-49%10`).
- **Delete `processors<N>/`** after a successful merge. It's a full second copy of the results.
- **`kill-shared`** has many idle cores, but jobs there can be killed. Only use it with
  `writeInterval` set, so a killed run can restart (`RESTART=1`).
