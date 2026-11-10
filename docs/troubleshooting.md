# Troubleshooting

Problems we actually hit, and their fixes.

| Symptom | Cause | Fix |
|---|---|---|
| `apptainer: command not found` | You're on a login node | Use `srun ... --pty /bin/bash` or submit with `sbatch` |
| `Illegal option --` / `Usage: /usr/bin/which [-a] args` inside the container | Koa exports a `which` shell function with RHEL-only options, and the container's Ubuntu `which` rejects them | Use `command -v` instead of `which` |
| `unzip: command not found` | The login nodes don't have it | `python3 -m zipfile -e file.zip .` |
| `sbatch: error: This does not look like a batch script` | The first line of the script isn't `#!/bin/bash` (for example, an editor changed it) | Make `#!/bin/bash` the first line. Directives must start with `#SBATCH`, not `#BATCH` |
| `syntax error near unexpected token '&&'` after pasting commands | The terminal merged several pasted lines into one, so a variable like `OF=...` never got set | Paste one command at a time, or put the commands in a script file |
| Pasted terminal output gives lots of `command not found` | Output was pasted back into the shell along with the command | Harmless. Copy only the command line |
| Image build runs for hours | Apptainer cache/temp on Lustre scratch | Use `container/build_image.slurm`, which builds on node-local `/tmp` |
| Job ends with `TIMEOUT` after `waveFoam` finished | Reconstructing many output times takes a long time | `sbatch --export=ALL,RECON_ONLY=1 run_case.slurm` |
| `reconstructPar` very slow (minutes per time) | ascii output + one file per core on Lustre | `writeFormat binary;` + collated output (the default in `run_case.slurm`) |
| Job pending a long time with `(Priority)` or `(Resources)` | The cluster is busy, or the core count only fits on a few nodes | Ask for 24 cores rather than 32/40. Check `sinfo -o "%15P %20C"` and `squeue -u $USER --start` |
| ParaView shows nothing, or "Decomposed Case" finds no data | Collated `processors24/` can't be read by ParaView | Use **Reconstructed Case** |
| Headless ParaView: `libglapi.so.0: cannot open shared object file` | WSL/Ubuntu lacks Mesa libraries the ParaView build expects | Run `postprocessing/setup_paraview_linux.sh` |
| Monitoring shows an old time or a run that "finished" instantly | You're reading the `waveFoam.log` copied from the workstation | Check the log's date (`ls -l waveFoam.log`) and the `Date :` line at its top |
| `sacct: error: ... Connection refused` | Koa's accounting database is temporarily down | Harmless. Use `squeue` and the logs instead |
| `bounding k, min: ...e-17` in the solver log | Tiny negative turbulence values clipped to zero, common in wave runs | Harmless at these magnitudes |

## Getting help

- UH ITS Cyberinfrastructure (Koa support): uh-hpc-help@lists.hawaii.edu
- waves2Foam: [OpenFOAM wiki page](https://openfoamwiki.net/index.php/Contrib/waves2Foam) and the
  CFD Online forum
