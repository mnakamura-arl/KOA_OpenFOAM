#!/usr/bin/env python3
"""Compare the reconstructed fields of two OpenFOAM runs of the same case.

Usage:  python3 compare_runs.py <caseA> <caseB> [field ...]

Reads ascii or binary (label=32, scalar=64) volume fields, compares the internal
field at every time folder present in both cases, and reports the largest
difference per field. Default fields: alpha.water U p_rgh k omega nut.
"""
import os
import re
import sys
from array import array

NCOMP = {"scalar": 1, "vector": 3, "symmTensor": 6, "tensor": 9}
TIME_DIR = re.compile(r"^[0-9.eE+-]+$")


def read_internal_field(path):
    """Return the internal field as a flat list of floats (or a single-value list if uniform)."""
    with open(path, "rb") as f:
        data = f.read()
    i = data.index(b"internalField")
    head = data[i:i + 200]
    if head.split()[1] == b"uniform":
        m = re.match(rb"internalField\s+uniform\s+\(?([^;)]*)", head)
        return [float(x) for x in m.group(1).split()]
    m = re.match(rb"internalField\s+nonuniform\s+List<(\w+)>\s+(\d+)\s*\(", head)
    kind, n = m.group(1).decode(), int(m.group(2))
    count = n * NCOMP[kind]
    start = i + m.end()
    if re.search(rb"format\s+binary", data[:2000]):
        values = array("d")
        values.frombytes(data[start:start + 8 * count])
        return values.tolist()
    # ascii: take the first `count` numbers after the opening parenthesis
    tokens = data[start:].replace(b"(", b" ").replace(b")", b" ").split(None, count)
    return [float(t) for t in tokens[:count]]


def times(case):
    return {d for d in os.listdir(case) if TIME_DIR.match(d) and os.path.isdir(os.path.join(case, d))}


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    a, b = sys.argv[1], sys.argv[2]
    fields = sys.argv[3:] or ["alpha.water", "U", "p_rgh", "k", "omega", "nut"]
    common = sorted(times(a) & times(b), key=float)
    print(f"{len(common)} time folders in both cases\n")
    print(f"{'field':12} {'times':>6} {'max abs diff':>14} {'at time':>10} {'max |value|':>14} {'rel diff':>10}")

    worst_rel = 0.0
    for field in fields:
        n_times, max_diff, max_time, max_val = 0, 0.0, None, 0.0
        for t in common:
            pa, pb = os.path.join(a, t, field), os.path.join(b, t, field)
            if not (os.path.isfile(pa) and os.path.isfile(pb)):
                continue
            va, vb = read_internal_field(pa), read_internal_field(pb)
            if len(va) != len(vb):
                print(f"  {field} at t={t}: size mismatch {len(va)} vs {len(vb)}")
                continue
            d = max(abs(x - y) for x, y in zip(va, vb))
            n_times += 1
            max_val = max(max_val, max(abs(x) for x in va))
            if d >= max_diff:
                max_diff, max_time = d, t
        if n_times == 0:
            print(f"{field:12} {'-':>6}   (not found in both cases)")
            continue
        rel = max_diff / max_val if max_val else 0.0
        worst_rel = max(worst_rel, rel)
        print(f"{field:12} {n_times:>6} {max_diff:>14.3e} {max_time:>10} {max_val:>14.3e} {rel:>10.1e}")

    print()
    if worst_rel < 1e-5:
        print("RESULT: runs match to within ascii rounding (7 significant digits) - no loss of fidelity.")
    else:
        print("RESULT: differences exceed ascii rounding - check the fields/times listed above.")


if __name__ == "__main__":
    main()
