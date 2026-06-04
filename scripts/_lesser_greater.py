#!/usr/bin/env python3
"""Compute Election sorted-list lesser/greater neighbours for a group whose
total vote count changes to `new_total`.

Input file holds the two return arrays of
`Election.getTotalVotesForEligibleValidatorGroups()` as printed by `cast call`:
  line 1: [0xaddr, 0xaddr, ...]
  line 2: [1234 [1.2e3], 5678 [5.6e3], ...]   (cast appends sci-notation hints)

The Celo Election sorted LinkedList is descending by vote weight:
  - greater = node immediately ABOVE the group's new slot (more votes)
  - lesser  = node immediately BELOW the group's new slot (fewer votes)
address(0) when no such neighbour exists.

Usage: _lesser_greater.py <file> <group_addr> <new_total>
Prints: "<greater> <lesser>"
"""
import re
import sys

ZERO = "0x0000000000000000000000000000000000000000"


def main() -> None:
    path = sys.argv[1]
    group = sys.argv[2].lower()
    new_total = int(sys.argv[3])

    lines = [ln for ln in open(path).read().splitlines() if ln.strip()]
    addrs = re.findall(r"0x[0-9a-fA-F]{40}", lines[0])
    # Values line: take the leading integer of each comma-separated token,
    # ignoring cast's "[1.2e3]" scientific-notation annotations.
    val_line = lines[1].strip().lstrip("[").rstrip("]")
    vals = []
    for tok in val_line.split(","):
        m = re.match(r"\s*(\d+)", tok)
        if m:
            vals.append(int(m.group(1)))

    n = min(len(addrs), len(vals))
    d = {addrs[i].lower(): vals[i] for i in range(n)}

    others = sorted(
        ((a, v) for a, v in d.items() if a != group),
        key=lambda kv: -kv[1],
    )
    above = [a for a, v in others if v >= new_total]
    below = [a for a, v in others if v < new_total]
    greater = above[-1] if above else ZERO
    lesser = below[0] if below else ZERO
    print(f"{greater} {lesser}")


if __name__ == "__main__":
    main()
