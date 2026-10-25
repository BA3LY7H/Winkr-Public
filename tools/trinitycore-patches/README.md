# TrinityCore generator patches

Everything here exists because **stock TrinityCore cannot produce this repo's
navmesh**. The tuned bake needs generator flags that TC does not have, and the
audit tool does not exist upstream at all. These patches lived only as
uncommitted working-tree changes in `C:\tc\TrinityCore` — one `git checkout .`
away from being lost, on a machine with no restore points.

Losing them would silently break [`../bake_mmaps.sh`](../bake_mmaps.sh): it would
still run, passing flags the binary does not understand, and quietly produce a
STOCK bake instead of the tuned one.

## Base

    d9523a08  Core: Updated allowed build to 12.1.0.69465   (master)

## Contents

| file | what |
|---|---|
| `generator-tuning.patch` | 628 lines across 10 files. Adds the `--simplify`, `--detailDist`, `--detailError`, `--agentHeight`, `--agentClimb`, `--agentRadius` and `--fineBaseUnit` command-line options, and the `MMAP::g_*` tunables they drive. Also the Classic-side extractor changes. |
| `ClassicWdt.h` | Classic WDT parsing for the map extractor. |
| `mesh_audit/` | The auditor. Reports rejected tiles, unroutable pairs, storey ambiguity and through-wall segments. Not an upstream tool. |

## Applying to a fresh clone

    git clone https://github.com/TrinityCore/TrinityCore.git
    cd TrinityCore && git checkout d9523a08
    git apply /path/to/generator-tuning.patch
    cp /path/to/ClassicWdt.h src/tools/extractor_common/
    cp -r /path/to/mesh_audit src/tools/
    # then configure + build the tools as usual

The parameter VALUES, and why each differs from TC's defaults, are documented in
[`../bake_mmaps.sh`](../bake_mmaps.sh) — that file is the reason to read this one.
