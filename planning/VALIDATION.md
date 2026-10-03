# Validation and analysis strategy

This plan supports the [roadmap](ROADMAP.md) and [finding register](ANALYSIS.md). Targets below are acceptance criteria to implement, not results already achieved. The historical baseline remains 710 passing assertions plus the separate reproduced failures in the evidence archive.

## Core invariants

| Invariant | Required evidence | Finding/work-package coverage |
|---|---|---|
| Every mutation and persisted project belongs to the intended queue entry | Full-server transition tests with stable IDs, gesture targets and stale-event cases | A02–A04, A11–A12; T01–T03/T10–T11 |
| Only exact validated source metadata authorizes reopening and alignment | Prefix/duplicate-key rejection, conservative legacy handling and installed restart | A33; T03/T06/T07/T09b |
| “Saved” means the intended revision has a durable, readable checkpoint | Fresh-process resume and injected write/replacement failure tests | A01, A23; T03 |
| IDs and output paths are unique in their declared scope | Duplicate names, restart, populated-layer import, and path-boundary tests | A07–A09, A22; T01/T09 |
| Coordinates and declared levels refer to the same grid | Independent transform fixtures and vector/raster round trips | A06, A16, A18, A21; T05 |
| Mask support is independent of optimization choice | Independent tiny-grid oracle and optimized/general comparisons | A05, A15; T04 |
| Code values preserve label meaning and encoding | Categorical, instance, binary, and bitfield reference fixtures | A17, A19–A20; T06/T13 |
| Malformed files never become fabricated complete arrays | Handwritten short/invalid payload fixtures and size/range assertions | A10, A13–A14, A26–A30, A32; T07/T08 |
| Browser geometry and routing match server semantics | Real-browser multiwidget, holes, history, and navigation journeys | A24–A25; T10/T11 |
| Analytical results have correct units, denominators, and provenance | Independently calculated counts/statistics and repeatable reports | O05; T12–T14 |
| Large-data claims have measured resource bounds | Cold-process open/window/queue/export benchmarks | O01; T15–T17 |

## Test layers and execution lanes

Use existing testthat infrastructure for R behavior and Shiny's server test facility for app state. Choose the browser automation runner during T10 based on repository/runtime compatibility; do not add an unqualified dependency merely to implement this document.

| Lane | What runs | When | Failure policy |
|---|---|---|---|
| Core deterministic | Validators, identity, geometry, masks, parser fixtures, selected analytical formulas | Every relevant change / pull request | Mandatory; no silent skips for a required capability |
| Integration | Save/load, fresh R process, full Shiny server, duplicate-source/export cases | Every relevant change / pull request | Mandatory for persistence, app, or I/O changes |
| Browser | Small end-to-end journeys, two widgets, geometry hits, dependency failure UI, keyboard/focus behavior | App/widget changes and every release | Mandatory for supported app configurations |
| Independent interchange | Externally written NPY/ENVI fixtures and independent consumption of exported arrays | I/O changes and every release | Mandatory for claimed core formats |
| Optional backend | Bio-Formats/Cubert and other qualified configurations with permitted fixtures | Scheduled/available runners and capability release | Required to claim that specific configuration; unavailable means unverified |
| Performance | Cold/warm reads, queues, previews, streaming exports, peak memory | Backend/performance changes and release candidates | Correctness/resource-bound failures block; noisy timing needs repeat/analysis |
| Package/release | Build, dependency checks, examples, vignettes, documentation, selected OS/R configurations | Pull requests through shared CI; full release qualification | Errors and unexplained warnings block; notes reviewed explicitly |

Keep heavy real-file and performance jobs out of the default tiny-fixture lane. Explicitly distinguish “not installed,” “fixture unavailable,” and “not supported.” A skip must identify the capability left unverified.

## Persistence and full-server scenarios

Use tiny real image files with different pixel patterns and different queue-entry IDs. Do not use identical copied pictures as the only image-identity oracle: a wrong image may look correct.

| Scenario | Expected result |
|---|---|
| Draw → Save → next → previous | Same entry identity, image pixels, ROI geometry, label, and revision |
| Draw → next → previous with autosave disabled | In-memory edits retained; disk writes occur only at explicit save/commit |
| Draw → Undo → Redo with autosave enabled | Saved revision eventually matches live revision; indicator reflects transitions truthfully |
| Draw on A → navigate to B → Undo | B's history applies; A cannot replace B's project |
| Draw on A → Shift+Enter | A is persisted and marked complete, then navigation advances |
| Shift+Enter on final entry | Exactly one valid commit; cursor stays in bounds; no duplicate action |
| Save failure during commit/advance | Previous checkpoint intact; no advance or false complete/saved state |
| Replace queue while cursor is 1 | New session generation materializes its first image; old history/events cannot mutate it |
| Late draw/edit event from prior image | Rejected by entry/revision check rather than applied to the new image |
| Same filename across directories, same source twice | Entries and output artifacts remain independently addressable |
| End process → reopen in a fresh process | Source descriptor reconstructs tile access, ROI IDs stay unique, existing annotations survive |
| Missing or moved source on resume | Annotation data remains available; explicit relink/error behavior, no guessed replacement image |
| Legacy schema load and next save | Defined migration, original retained, compatibility recorded |

Inject failure before writing, during checkpoint creation, and during final replacement. Assert file contents/checkpoint identity after failure, not merely that an error was thrown. Test replacement semantics on each supported OS. Avoid polling/sleep-based race tests when event identity and deterministic transition functions can express the requirement.

## Geometry, masks, and independent expected results

Maintain fixtures small enough to inspect directly, primarily 10×10 grids and a few non-square grids. Store expected integer matrices as fixtures or derive them from independent mathematical expressions. Do not derive expected results with annotatR's own rasterizer.

- Shapes: axis-aligned rectangles, the three-corner rectangle-like triangle, sloped polygons, holes, multipolygons, points at integer/fractional/boundary positions, thin lines if supported, empty and repaired geometries.
- Grid cases: non-square images, out-of-bounds shapes, half-pixel edges, lower/upper ties, very small regions, adjacent regions sharing a border, one versus multiple unrelated ROIs.
- Transform cases: same level, power-of-two, non-power-of-two, anisotropic x/y ratios, forward/inverse transforms, mixed-level operations with and without sufficient image metadata.
- Encoding cases: empty/binary/instance/categorical masks, nonzero backgrounds, code collisions, explicit mappings, bitfields with composite pixels, absent classes, invalid mappings.
- Algorithm cases: touches on/off, every declared overlap policy, general/optimized paths, and each advertised rasterization engine.

Require exact equality for integer masks, class mappings, dimensions, identifiers, and counts. Use a documented absolute tolerance of at most `1e-8` level-zero pixels for the small coordinate round-trip fixtures; calibrate a justified tolerance separately for larger coordinates and geometric repair. Do not widen tolerances simply to accommodate a regression. Polygon approximation/repair should be tested for the documented behavior, not assumed to preserve original area exactly.

Use metamorphic checks as a second line of defense: adding a disjoint ROI cannot change existing support, renaming a label cannot move pixels, a reversible coordinate transform preserves its geometry within tolerance, and a cache hit returns the same values as a cache miss. These checks complement independent fixtures rather than replace them.

For connectivity, a diagonal two-pixel pattern must produce the documented difference between 4 and 8 connectivity. Verify actual polygon topology and component membership, not just accepted arguments.

## Interchange and binary-file matrix

| Format | Minimum independent fixtures | Required checks |
|---|---|---|
| ENVI | BSQ/BIL/BIP; supported integer/float types; both endians; offset 0/nonzero; non-square cube | Known band/x/y values including full signed int32 boundaries, correct byte offsets, header validation, short payload rejection |
| NPY | External C/Fortran arrays; supported signed/unsigned widths and header versions; non-square shape | Exact dtype/range handling, endian/order correctness, malformed-header and truncated-body rejection, overflow rejection |
| TIFF/PNG mask | Independently read/written fixtures for each supported depth/backend combination | Exact integer class codes including16-bit PNG, dimensions/orientation, sidecar mapping, optional backend fallbacks, requested depth on constant/extrema masks |
| GeoJSON/CSV | Explicit coordinate levels; multiple ROI levels; independently inspected coordinates | Export level equals coordinate level, metadata precedence, stable valid IDs, documented legacy ambiguity |
| QuPath | Permitted fixtures from the supported consumer version | Geometry, current/legacy class and object fields, native feature arrays/collections, explicit ID mapping, successful independent import/export; version recorded |
| RDS project/session/mask | Legacy valid samples, stripped handles, current schema, intentionally invalid structures | Validation, migration, embedded legends, source reopening, overwrite semantics, checkpoint recovery |

Record expected values separately from fixture generators. Generating a file with annotatR and reading it back with annotatR is useful integration coverage but insufficient interoperability evidence. Where an external application is required, retain a small reproducible import/export recipe and record its exact version.

ENVI's header-offset requirement is described in the [vendor format documentation](https://www.nv5geospatialsoftware.com/docs/enviheaderfiles.html). Verify other format/API details against the relevant primary specifications during implementation rather than relying on memory or a matching filename extension.

## Quantitative analysis reference cases

Construct a synthetic cube with an explicit formula such as `value(y,x,b) = 100*b + 10*y + x`, using clearly documented one-based array indices. It has independently calculable ROI values and makes band swaps, x/y transpositions, and wrong-source cache hits visible. Add constant and gradient bands, a known wavelength table, and optional known physical pixel sizes.

| Analysis case | Acceptance criteria |
|---|---|
| Per-ROI mean/median/min/max/sum/SD/count | Match independent calculations; distinguish sample SD convention and singleton behavior |
| Missing/nonfinite samples | Explicit policy; report selected and contributing counts; no unexplained Inf/NaN summaries |
| Point, thin, empty, outside-image ROI | Consistent mask/extraction support and documented empty-result behavior |
| Spectra | Correct band-to-wavelength mapping, wavelength units, order, and source; display stretch does not alter raw values |
| Physical area | Known anisotropic pixel size produces expected units/area; unknown calibration stays unknown |
| Bitfield statistics | Each class includes composite memberships; sum of class memberships may exceed foreground count |
| Agreement | Identical/disjoint/partial/empty cases match independent contingency tables; absent-class policy documented |
| Class-code remapping | Same label with different codes requires alignment or a clear error; never silently compares different labels |
| Instance masks | Require explicit instance matching or rejection for a metric intended for semantic labels |
| Aggregate summary | Per-image/ROI/pixel aggregation is explicit; denominators and exclusions are recorded |
| Repeated report | Same inputs and settings produce identical deterministic tables and a complete provenance record |

Proposed report fields: source and queue-entry IDs, annotation revision, ROI ID/layer/label, image dimensions, level/transform, mask encoding and code map, selected/contributing/excluded pixel counts, wavelength/calibration units, statistics and aggregation policy, package/backend versions, and configuration identifier. Avoid exposing raw local paths where an exported identifier is sufficient.

Do not select inferential thresholds or sampling units from software convenience. The data owner must specify the independent unit for study-level uncertainty. If a demonstration includes resampling, declare that unit and seed; do not treat all pixels from a single image as independent observations by default.

## Browser journeys

Run a compact set of real-browser journeys over fixtures with distinguishable images. Assert server state and exported output after interaction as well as checking visible feedback.

1. Start with the supported minimal dependency configuration; load a real image, choose a label, draw, undo/redo, save, navigate, close, and resume.
2. Draw/edit a polygon with a hole and a multipolygon; click the hole; verify selected ROI identity, geometry, and exported support.
3. Mount two canvases; send independent tools/annotations/overlays; remove/remount one; verify the other continues functioning.
4. Switch image while an event or drawing is unfinished; late events cannot mutate the new project.
5. Exercise locked/hidden layers, z-order, keyboard shortcuts, text-field focus, cancellation, and missing display dependencies.
6. Export a queue with duplicate basenames, one empty image, and an injected failure; receipt and downloaded contents agree.

Visual snapshots can help catch alignment and layering errors, but coordinate and pixel assertions remain the primary oracle. Test at different canvas sizes and a non-default display scale. Establish supported browser versions during T10/T18 qualification; the present audit did not do so.

## Performance measurements and provisional targets

Use a separate process for each cold-start memory measurement. Record R/package/system-library versions, CPU/RAM, storage type, source file bytes, dimensions/bands/levels, ROI count/vertices, cache size, and test seed. Measure before opening the image. Test a small raster, a representative spectral cube, an anisotropic pyramid, and a permitted large-image fixture. Synthetic large files should be bounded and cleaned up explicitly.

| Workload | Measure | Initial proposed acceptance target |
|---|---|---|
| Metadata open on a window-capable backend | Bytes read, peak RSS, elapsed time | No full pixel-array allocation; record backend-specific header/index costs |
| Fixed 256×256 window at two substantially different file sizes | Pixel equality, bytes read, incremental RSS | Resource cost determined by the window/index/compression layout, not a full decoded cube |
| Warm window | Pixel equality, hit/miss behavior, latency | Identical values and no stale hits across source generations/options |
| Image/overlay preview | Returned dimensions, allocation, latency | Configured maximum dimensions honored, including non-pyramidal sources |
| 100-entry navigation with bounded cache/history | Memory trajectory, open handle count | Memory reaches a documented steady bound after eviction instead of growing per visited image |
| Small edit and preview refresh | End-to-end latency | Provisional p95 ≤250 ms on agreed hardware/fixtures; benchmark before adopting as a gate |
| Annotation-only save | Time and serialized size | Size scales with annotations/metadata, not embedded cube bytes; provisional p95 ≤1 s on agreed small fixtures |
| Full mask export | Peak RSS, correctness, cancellation | Streaming uses bounded tile buffers; exact match to in-memory reference for supported overlap policies |

The latency numbers are proposed budgets, not measurements or promises. T17 must calibrate them and document the supported workload envelope. Prefer structural memory/read-volume assertions in mandatory CI. For scheduled timing comparisons, collect repeated samples, report distribution and environment, and investigate sustained regressions before setting a numeric blocking threshold.

A full matrix returned by `at_mask()` necessarily occupies memory proportional to its dimensions. Large-slide support must therefore distinguish bounded source access, bounded previews, bounded streaming export, and materialized-mask APIs. Claims such as “larger than memory” need evidence for the complete advertised operation.

## Release gates and completion evidence

**Stabilization gate:** all A01–A33 have failing-before/passing-after regressions and no unresolved cross-image, persistence, mask, or encoding ambiguity in supported workflows. Run core/integration/browser lanes, independent core-format fixtures, and legacy migration fixtures. Reconcile documentation with capabilities. Existing tests and package examples must continue passing; complete applicable vignette/manual checks and review packaging notes. A skipped optional backend is listed as unverified and excluded from new support claims.

**Analysis gate:** T12–T14 reference calculations pass; output units, mappings, missing-data policy, denominators, and provenance are explicit. Independently reproduced tables and configuration accompany the release evidence. Do not equate this gate with validation of a particular scientific study.

**Extended-support gate:** windowed reads, memory bounds, and qualified optional formats pass on recorded configurations and permitted fixtures. Streaming results match reference masks. Repeat legacy compatibility and browser journeys after backend changes.

For each closed finding retain: finding ID, implementing revision, test name/fixture, prior failure, corrected result, relevant dependency versions, migration implications, and reviewer/date. Coverage is a supporting signal: measure the baseline, require all identified critical scenarios, and ratchet relevant branch/line coverage without counting optional skips as exercised behavior.

Documentation-only planning changes require link, mapping, syntax, and package-exclusion checks. They do not justify rerunning the complete unchanged runtime suite. When the archived diagnostic scripts are made portable, parse them and run representative diagnostics to verify those edits; preserve historical baseline logs separately from new run output.
