# Rendering performance baseline

Reference numbers for the canvas render path, captured with the DEBUG-only
`PerfLog` probe (`GET /perf`, `just inspect-perf`). Use these as the target when
changing the compositor (for example the opacity-flattening work).

## How to reproduce

1. `just run-bg` (launches with `--dev --port 9876`).
2. `just inspect-perf-reset`.
3. Draw a known workload through `/pointer` (the table below uses four strokes of
   twelve move events each, on a near-empty canvas).
4. `just inspect-perf` to read the aggregated stats.

Labels: `render.bake` (committed bake compositing), `draw.inProgress` (live
in-progress stroke), `draw.total` (whole `draw(_:)`). Gauges report the canvas
device size.

## Conditions

- Debug build (the scalar paths are unoptimized; Release is faster).
- Canvas 3840x2160 at backing scale 1. A 2x retina display is roughly 4x more pixels.
- macOS, Apple Silicon.

## Baseline: source-over, no flattening

`main` at `6921dc2` + the perf probe (`5160d2e`). This is the long-standing
behavior: overlapping same-color marks darken at their intersection.

| Path | mean | max | calls (4 strokes) |
|------|------|-----|-------------------|
| `render.bake` | 2.6 ms | 3.4 ms | 4 |
| `draw.inProgress` | 0.17 ms | 0.35 ms | 39 |
| `draw.total` | 0.18 ms | 0.40 ms | 43 |

Smooth: every path is well under the 16 ms per-frame budget. `LayerPlan`
grouping (when present) measured 0.03 ms and is not a factor.

## Opacity flatten attempt v1 (for contrast)

`opacity-flattening-v1` branch. The compositor drew each item into its own
full-canvas pixel buffer and walked every pixel taking the max alpha, which is
O(items x whole canvas).

| Path | mean | max | calls (4 strokes) |
|------|------|-----|-------------------|
| `render.bakeCommitted` | 1187 ms | 3760 ms | 8 |

About 450x slower on the bake, and it grew with stroke count (each added
same-color mark was another full-canvas draw plus pixel walk). The branch's
`draw.liveComposite` read ~0.01 ms, but that is an artifact: a background
window's draw context is degenerate, so the live composite collapsed to
near-zero. On screen it would have been bake-scale. The baseline's
`draw.inProgress` (a real source-over draw) is 0.17 ms, an order of magnitude
more than that artifact, which confirms it.

## Target

Any flattening approach should keep `render.bake` (and any live compositing) in
the single-digit-millisecond range, like the baseline, and must not scale cost
with the whole canvas area per item.
