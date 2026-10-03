# Audit regression contracts and baseline

Prepared 2026-09-10. Runtime under test: `f69bf201f651c845ab496f76e25638bc919d4b13` (annotatR 0.1.0), with new regression specifications only. All A01–A25 remain open. These assertions describe intended behavior; their expected failures are deliberately retained until the implementing work packages repair the runtime. Historical diagnostic output is preserved unchanged in [the evidence archive](evidence/2026-09-10/README.md).

## Execution and observation

Run from the repository root, with development dependencies installed:

```sh
Rscript tests/audit/run-regressions.R geometry
Rscript tests/audit/run-regressions.R io
Rscript tests/audit/run-regressions.R mask
Rscript tests/audit/run-regressions.R persistence
Rscript tests/audit/run-regressions.R app
node --test --test-reporter=tap tests/audit/widget.test.js
```

Each command exits **1 on this baseline**. The R runner disables testthat's ten-failure cutoff and prints assertion messages and dependency versions; the focused groups ensure each finding is exercised. It uses `test_local()` against this checkout. Standard testthat discovery also includes all five `test-audit-*.R` files. The standalone Node tests use only built-in Node modules. No test passes by expecting a known incorrect diagnostic value, and no mandatory fixture depends on the ignored workbench.

| Group / observed output | Cases | Failed assertions | Error cases | Passed assertions | Warnings / skips |
|---|---:|---:|---:|---:|---:|
| [geometry](evidence/2026-09-10/regressions/geometry.log) | 7 | 13 | 0 | 1 | 0 / 0 |
| [io](evidence/2026-09-10/regressions/io.log) | 5 | 4 | 0 | 2 | 0 / 0 |
| [mask](evidence/2026-09-10/regressions/mask.log) | 7 | 11 | 1 | 2 | 0 / 0 |
| [persistence](evidence/2026-09-10/regressions/persistence.log) | 5 | 9 | 0 | 3 | 0 / 0 |
| [app](evidence/2026-09-10/regressions/app.log) | 5 | 11 | 0 | 6 | 0 / 0 |
| [widget](evidence/2026-09-10/regressions/widget.log) | 5 | 5 failing cases | 0 | 0 passing cases | 0 / 0 |

R results count expectations, whereas Node reports cases. The one R error is the known A14 explicit `connectivity=4L` rejection; a separate default-connectivity assertion reaches polygonisation and fails independently. The complete NPY control passes, as do basic source/area/identity controls inside failing cases; these partial passes do not close findings.

Recorded stack: R 4.6.1, Linux x86_64, pkgload 1.5.3, testthat 3.3.2, sf 1.1.2, stars 0.7.3, terra 1.9.34, tiff 0.1.12, shiny 1.14.0, ggplot2 4.0.3, magick 2.9.1; GEOS 3.14.1, GDAL 3.12.2, PROJ 9.7.1. Node v24.19.0. Detailed R versions are repeated in each log. Optional dependencies missing on another host cause explicit skips, not a supported-format claim.

The A01/A09 TIFF oracles were corrected before closure work: `tiff::writeTIFF()`
maps numeric samples 0/1 to stored 8-bit samples 0/255. The fixtures now declare
`bits.per.sample = 8L` and uncompressed storage, and Python `tifffile` independently
confirmed raw A01 samples 0,255,255,0 and raw A09 samples all 255 in the second
file. The corrected cases were independently reconfirmed RED against the untouched
baseline ([log](evidence/2026-09-10/regressions/corrected-tiff-oracles-red.log)).
This corrects the oracle only; backend values remain raw and are not rescaled.

## Finding contracts and owners

Owners below are the roadmap work-package maintainer responsible for closure; T00 maintains this register and evidence. Test names begin with stable audit IDs. Filenames are relative to `tests/testthat/` unless stated otherwise.

| Finding | Owner | Regression | Proposed contract / independent expected result | Baseline observation |
|---|---|---|---|---|
| A01 | T03 | `test-audit-persistence.R` | Lightweight project loaded in a fresh R process reopens its 2×2×1 TIFF with raw 8-bit samples 0,255,255,0 | Tile and dimensions are NULL |
| A02 | T02 | `test-audit-app.R` | Commit/advance stores one drawn ROI in first queue project and displays second source | First slot is NULL; first source occupies second slot/live view |
| A03 | T02 | `test-audit-app.R` | Undo on entry two cannot restore entry one's project | Cursor two displays first source |
| A04 | T02 | `test-audit-app.R` | Folder replacement at cursor one must load the new manifest source | Old source remains live |
| A05 | T04 | `test-audit-geometry.R` | Literal 15-pixel triangle matrix under the tie convention below, alone and in a layer | Single mask has 25 pixels; batch mask differs on diagonal ties |
| A06 | T05 | `test-audit-geometry.R`, separate JSON/CSV cases | Read/export coordinates and level metadata together preserve level-zero bbox (4,4,10,10), area 36 | Both return bbox (8,8,20,20), area 144 |
| A07 | T01 | `test-audit-persistence.R` | Fresh-process addition preserves four existing IDs and creates one unique fifth ID | Fifth ID duplicates an existing ID |
| A08 | T01 | `test-audit-persistence.R` | Two successful same-basename exports have distinct paths and labels first/second | One unique path, second/second labels |
| A09 | T01 | `test-audit-io.R` | Identical relative paths in different directories return their own 2×2 raw 8-bit zero/255 pixels | Second file returns zeros |
| A10 | T07 | `test-audit-io.R` | ENVI offset skips the sentinel; BSQ rows are (1,2), (3,4) | Sentinel 999 appears as first pixel |
| A11 | T02 | `test-audit-app.R` | After undo, any saved indicator agrees with zero live, in-session and disk checkpoint ROI counts | Indicator saved while both stored counts remain one |
| A12 | T02 | `test-audit-app.R` | Autosave-off next/previous preserves one ROI and its ID in session memory | ROI and ID disappear |
| A13 | T07 | `test-audit-io.R`, separate ENVI/NPY cases | Declared 2×2 arrays with only two samples raise a payload error; complete independent C-order NPY is [[1,2],[3,4]] | Truncated inputs accepted; complete control passes |
| A14 numeric | T08 | `test-audit-mask.R`, bits/connectivity cases | Explicit integer bits 8/16 and connectivity 4/8 are valid | All four choices rejected |
| A14 connectivity | T08 | `test-audit-mask.R`, separate default-eight/four cases | Two diagonal foreground pixels are one region under eight-connectivity, two under four-connectivity; total area two | Default eight returns two regions; explicit four blocked by numeric validator |
| A15 | T04 | `test-audit-geometry.R` | Integer point (5,5) belongs to half-open cell at R [6,6]; extraction returns one row with value 56 | Mask selects [5,5]; extraction returns zero rows |
| A16 | T05 | `test-audit-geometry.R` | Bare mixed-level ROIs without image scale context are rejected, preventing guessed level ratios | Difference proceeds silently |
| A17 | T06 | `test-audit-mask.R` | Binary background 1 collides with foreground and must raise a clear error | Silently returns an empty binary mask |
| A18 | T05 | `test-audit-geometry.R` | Rendered downsampled image bounds stay [0,2048]×[0,8] in level-zero coordinates (negative y in built reversed plot) | Built raster bounds [.5,1024.5]×[-4.5,-.5] |
| A19 | T06 | `test-audit-mask.R` | RDS mask restores label tumour with area nine | Label becomes 1; area control passes |
| A20 | T06 | `test-audit-mask.R` | Two 6×6 class memberships have counts 36/36, fractions .36/.36, x-centroids 3/7; stride-two preview counts 9/9 | Counts 32/32, fractions .32/.32, centroids 2.75/7.25, preview 8/8 |
| A21 | T05 | `test-audit-geometry.R` | Per-ROI export uses x scale four and y scale two: rows 5:10, columns 9:20, 72 pixels | Export has 36 pixels; project-mask independent control passes |
| A22 | T09 | `test-audit-persistence.R` | Project name ../escaped is rejected or safely encoded; all successful files stay inside destination | Outside TIFF created |
| A23 | T03 | `test-audit-persistence.R` | Default session path obeys overwrite FALSE; refused write leaves exact prior bytes intact | No error and checkpoint bytes replaced |
| A24 holes | T10 | `tests/audit/widget.test.js`, hit/display cases | Empty hole emits no erase; exterior remains selectable; both rings submitted to canvas | Hole emits erase; only exterior contour submitted |
| A24 MultiPolygon | T10 | `tests/audit/widget.test.js`, hit/display cases | Both disconnected components render and can be selected; gap does not select | No component contours drawn; component click ignored |
| A25 | T10 | `tests/audit/widget.test.js` | Messages addressed to widget A or B affect only that mounted instance | Creating B disables A's tool command |

### Coordinate decisions that change outputs

A05 uses centres `(j−0.5, i−0.5)`. For centres exactly on a polygon edge, evaluate membership at `(x+ε, y+ε²)` in the symbolic limit `ε→0+`. This preserves lower-inclusive, upper-exclusive ties for axis-aligned boundaries and resolves sloped boundaries without depending on the numeric perturbation chosen by a raster library. The triangle `(0,0),(5,0),(5,5)` includes its diagonal centres: foreground rows contain 5,4,3,2,1 pixels. The explicit 10×10 expected matrix is written literally in the test. Neither observed 25 nor historical 13 is used as an oracle. T04 must extend parity checks to winding, holes, multipolygons and reversed/sloped boundaries when implementing this convention.

A15 follows the documented half-open cell `[j−1,j)×[i−1,i)`. Therefore an integer point (5,5) belongs to row six, column six. This intentionally corrects the historical fastpath's row-five/column-five selection, in addition to fixing empty extraction. The existing raw 10×10 array is column-major: `(6−1)*10+6=56`. Geometry and valid stored IDs must not be rewritten to compensate.

A16 establishes the safe behavior for the current context-free set-operation API. A future image-aware operation should transform both geometries through declared level dimensions and return zero area for physically identical squares. That image-aware positive test belongs to T05 when the API exists; assuming a factor of two from level numbers alone is not an acceptable repair.

## Synthetic fixture inventory

Fixtures are generated inside temporary directories and cleaned up. They contain no private image data.

| Fixture | Definition | Used for |
|---|---|---|
| Tiny raw image | `tiny_image()` metadata plus 10×10×1 array 1:100 | Exact point extraction and masks |
| Pyramid metadata | Existing `small_image()` has 100→50→25 levels; separate 100×80→25×40 descriptor | Interchange and anisotropic export |
| Triangle / rectangles | Literal vertices and 10×10 expected matrices | Coverage, background and overlap semantics |
| Two-class overlap | [0,6)² and [4,10)², codes 1 and 2 | Independent area/centroid/membership and preview counts |
| Display strip | Zero-valued 8×2048×1 array with ROI x=1800..1900 | Default display downsampling without a large allocation |
| Binary source TIFFs | Uncompressed 8-bit 2×2 patterns or distinct 10×10 zero/255 files written by tiff | Cold resume, relative source identity, exports, real server queue |
| ENVI streams | Literal 2×2 float32 BSQ header/payload; four-byte sentinel or two-sample truncation | Offset, orientation and short reads |
| NPY streams | Independently written v1 header, C-order little-endian int32 samples | Complete orientation control and short reads |
| Diagonal mask | Literal RDS matrix [[1,0],[0,1]] | Four/eight region connectivity |
| Saved objects | Synthetic four-ROI project and synthetic sessions | Genuine fresh-process ID/pixel reopen, overwrite preservation |
| Canvas features | Polygon exterior/hole and two MultiPolygon components on 100×100 canvas | Geometry command/hit-testing and multiwidget routing |

## Supported-format test inventory

This records scenarios, not blanket format certification. Existing suite results remain in the historical archive; T00 executed the focused new regressions above.

| Format / capability | Existing synthetic coverage | New T00 coverage | Remaining qualification / owner |
|---|---|---|---|
| Raster images | `test-backend-raster.R`: generated RGB example, intensity range, extension detection | Distinct TIFF sources and synthetic raw display | Explicit PNG/JPEG codec fixture matrix and minimal-dependency decoding, T11/T16 |
| Multipage TIFF | `test-backend-tiff.R`: generated pyramid, channels and level sizes | Anisotropic metadata/export; cold TIFF resume | Compressed/tiled/big-endian/BigTIFF and actual windowed reads, T15/T16 |
| ENVI | `test-backend-envi.R`: BSQ/BIL/BIP uint16, float32/wavelengths | Independent offset and short-payload fixtures | Full dtype/endian/offset × interleave matrix, malformed/overflow headers, T07/T15 |
| TIVITA | `test-backend-tivita.R`: synthetic big-endian float32 orientation, wavelengths, malformed length | No new proprietary fixture | Public redistributable source specification/fixture qualification, T07/T17 |
| NPY | `test-io-npy.R`: independent C-order uint8, package round trips, transpose, legends/bitfields | Independent C-order int32 full/truncated payload | Wider dtype/endian/version/range/schema validation, T07 |
| TIFF/PNG/RDS masks | `test-mask-io.R` and `test-mask-bitfield.R` | Explicit bit depths, RDS semantics, connectivity, per-ROI TIFF pixels | PNG and fallback-reader fidelity plus invalid schema/codes, T06/T08 |
| GeoJSON / CSV | `test-io-geojson.R`, `test-io-csv.R` | Known level-zero bbox/area against pyramidal round trips | Hole/MultiPolygon and foreign-schema coordinates, T05 |
| QuPath | `test-io-qupath.R`: classification names, colours and detections | No new external-client fixture | Actual QuPath import/export and provenance, T05/T09 |
| Project/session RDS | `test-io-project.R`, `test-class-session.R` | Fresh process, byte-preserving refusal, queue state | Version migration, missing/changed source, interrupted transactions, T01/T03 |
| OME/qptiff / Cubert | `test-backend-optional.R`: detection, availability and informative missing-dependency errors | No new positive read | RBioFormats/Java or cuvis runtime plus redistributable exact-value fixture; optional matrix, T17 |

Ignored workbench integration tests are neither mandatory fixtures nor evidence of portable coverage. Missing OME/Cubert dependencies and absence of a qualified foreign file must be reported separately from successful capability-detection tests.

## Benchmark fixture inventory

T00 establishes the inventory only. No runtime/memory performance conclusions follow from correctness tests or preallocated arrays.

| Fixture / workload | Availability | Required measurement / owner |
|---|---|---|
| 8×2048 display strip; tiny TIFF/ENVI/NPY sources above | Defined and executed for correctness | Smoke latency only; too small for scaling conclusions |
| `test-perf.R` rectangle/point/batch/cache cases and preallocated large-image extraction | Existing synthetic checks | Keep correctness assertions; do not count preallocated extraction as full-load memory proof |
| File-backed increasing ENVI cubes, fixed small windows and selected bands | To generate from deterministic values in T15 | Cold/warm process RSS, bytes read, elapsed time, peak working memory |
| File-backed tiled TIFF pyramid, compression/level/window sweeps | To generate or select redistributable fixture in T16 | Decode footprint, tile access, display memory and latency |
| ROI-count sweeps with fixed geometry complexity plus complex holes/MultiPolygon | To generate in T04/T15 | Same exact expected masks before timing fast/general paths |
| Source identity replacement and LRU eviction under byte limits | Tiny identity fixture exists; scale fixture pending T01/T15 | Cache bytes, reopen cost, bounded growth and identity correctness |
| Optional OME/WSI/Cubert representative file | External prerequisite, T17 | Authorized/public fixture manifest, checksums, hardware and supported size envelope |

## Browser prerequisites for closure

The Node harness cannot prove filled hole pixels, device-pixel-ratio behavior, CSS scaling, real pointer/keyboard ordering, message registration semantics in an actual Shiny client, or listener cleanup. T10 must run a real Shiny session in Chromium/Playwright (available in the implementation environment) with two mounted widgets, holes and disconnected components. Verify shell/hole/gap hit-testing, edits, deletion, tool routing in both directions, resize, zoom/pan, remount and listener cleanup. Record the browser version, viewport/device scale, page errors, screenshots or pixel samples and emitted event payloads. A baseline page boot alone does not close A24/A25.

Likewise, A02/A03/A04/A11/A12 have direct real-server tests but need keyboard-driven browser journeys through the mounted app before workflow closure. This is a documented external execution prerequisite, not an excuse to count a simulated browser as complete validation.
