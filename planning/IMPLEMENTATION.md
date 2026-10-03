# Roadmap implementation record

Execution started 2026-09-10 from f69bf201f651c845ab496f76e25638bc919d4b13 on branch `improve/roadmap`, in the sibling `annotatR-roadmap` worktree. The original checkout and its planning files remain intact. Changes are uncommitted.

## Baseline

The tracked-source suite passes 700 assertions in 287 cases, with four explicit skips and no failures, errors, or warnings. The skips cover one absent optional-dependency scenario and three integrations requiring private workbench files. Those files are excluded from mandatory validation. The earlier audit's 710 passing assertions included ten assertions on private local data.

Test coverage is 87.11854% for instrumented package R code using `covr` with `type="tests"`. This is a starting measurement; it does not measure browser JavaScript or all Shiny module code. The shared house lint rules report five findings. A real Chromium browser successfully loaded the baseline Shiny app and rendered its example image without page errors.

## Progress

| Work | Status | Evidence |
|---|---|---|
| T00 regression specifications | Complete; review approved | 29 R cases and five Node cases exercise all 25 audit IDs; all six baseline regression commands fail as expected |
| T01 identity | Complete; review approved | A07/A08/A09, focused identity/session/backend/Shiny checks, and an installed-package two-process identity regression pass |
| T02 transitions | Complete; review approved | 62 focused cases/222 assertions pass; T03 subsequently qualifies disk writes; complete modern browser journeys remain T10/T11 |
| T03 persistence | Local implementation complete; review approved | A01/A23, legacy migration, injected rollback, and installed fresh-process tests pass; actual Windows-host qualification remains T18 |
| T04 pixel membership | Complete; review approved | 556 focused expectations and A05/A15 pass; independent triangle/window probes pass |
| T05 coordinate levels | Complete; review approved | 929 focused expectations; 204 scoped fix expectations; independent precision/plot probes pass |
| T06 mask metadata | Complete; review approved | Encoding/grid/bitfield/source contracts pass; final source fix has 215 scoped and 133 metadata expectations in distinct runs; T08 subsequently qualifies numeric choices |
| T07 reader correctness | Complete; review approved | 448 focused expectations (3 explicit skips), 142 optional-reader expectations, installed restart qualification, independent TIFF truncation/OME integer probes pass |
| T08 numeric options and mask I/O | Complete; review approved | 803 mask checks, 262 caller checks, 32 independent exports; transparency fix has 184 scoped passing expectations |
| T09 exports and QuPath | Complete; review approved | 449 focused checks, two native QuPath round trips, 261 exact-key parser fix checks |
| T09b exact provenance keys | Complete; review approved | 443 covering expectations and installed restart pass; exact outer image and nested metadata keys required |
| T10 widget geometry and events | Complete; review approved | 28 Node cases, 170 focused R assertions; actual Chromium geometry, proxies, remount and delayed image/overlay checks pass |
| T11 app workflow and recovery | Complete; review approved | 36 Node tests, 176 focused fix assertions; actual delayed-render, full app/export/resume and installed no-magick journeys pass |
| T12 independent analytical data | Complete; review approved | 43 focused assertions; 14 artifacts and 2 manifests reproduce twice; independent statistical, agreement and physical-area oracles |
| T13 quantitative extraction and agreement | Complete; review approved | 743 focused assertions; independent statistics, calibrated area and semantic agreement checks pass |
| T14 reproducible analytical summaries | Complete; review approved | 175 focused and 568 covering assertions pass; repeat runs produce identical ten-CSV/settings-JSON bundles and the executable vignette renders |
| T15 windowed image reads | In progress | Metadata-only open, exact raw windows, source freshness and resource telemetry |
| T18a native TIFF integration | Queued after T15 | Contain the dependency callback abort before further memory/integration work |
| T16–T18 | Pending | Interfaces and dependency order recorded in the roadmap |

The identity fixes close A07/A08/A09, and shared transitions pass A02/A03/A04/A11/A12 in their regression scenarios. Persistence fixes additionally pass A01/A23, and pixel membership fixes pass A05/A15. Coordinate-level fixes pass A06/A16/A18/A21. All original audit findings now have implemented task corrections; T11 additionally closes a reproduced delayed-render mutation-origin race. Final full-suite qualification is pending, so focused passes are not a claim that the complete suite is green. Legacy session migration is implemented; the remaining platform qualification is recorded explicitly.

Independent reader, writer, and native QuPath probes exposed [A26–A33](ADDITIONAL-FINDINGS.md), assigned to T07–T09b corrections and subsequent analytical and backend qualification. RBioFormats is available in a temporary library, and the installed QuPath application supports headless consumer checks; support claims remain subject to exact-value tests.

T07 corrects A10/A13/A26/A27/A28/A30. One broad run aborted inside native ImageMagick; isolated plotting passes with and without Java. The same native assertion recurred during T13's expanded plot slice. A dependency-only reproducer and native backtrace now show a TIFF warning reaching an ImageMagick callback during an R tiff read after an earlier ImageMagick TIFF read. Mitigation and final integration remain T18; see the [diagnostic evidence](evidence/implementation-2026-09-10/native-diagnostic/backtrace.log). Task-scoped review approval is not a full-suite qualification.

## Finding closure map

These statuses describe the uncommitted `improve/roadmap` worktree based on `f69bf20`; there is no implementation commit yet. A reviewed task and its focused scenarios do not establish full application or release qualification.

| Findings | Local status | Focused regression evidence |
|---|---|---|
| A01, A23 | T03 reviewed; actual Windows host pending | [Persistence contracts](../tests/testthat/test-persistence-contract.R), [legacy files](../tests/testthat/test-persistence-legacy.R), [installed restart](../tests/qualification/installed-persistence.R) |
| A02–A04, A11–A12 | T02 and T10/T11 reviewed; full app journeys pass | [State transitions](../tests/testthat/test-state-transitions.R), [app audit](../tests/testthat/test-audit-app.R), [real browser journey](evidence/implementation-2026-09-10/t02-browser-journey.md) |
| A07–A09 | T01 reviewed; T09 extends export receipts and path policy | [Identity](../tests/testthat/test-identity.R), [installed processes](../tests/qualification/installed-identity.R) |
| A05, A15 | T04 reviewed | [Literal pixel membership](../tests/testthat/test-pixel-membership.R) |
| A06, A16, A18, A21 | T05 reviewed | [Coordinate levels and precision](../tests/testthat/test-coordinate-levels.R) |
| A17, A19–A20 | T06 reviewed | [Mask encoding, counts and source metadata](../tests/testthat/test-mask-metadata.R) |
| A10, A13, A26–A28, A30 | T07 reviewed | [Independent reader fixtures](../tests/testthat/test-reader-correctness.R), [reader provenance](../tests/testthat/test-reader-provenance.R) |
| A14, A29, A32 | T08 reviewed; grayscale transparency rejected before conversion | [Exact raster I/O](../tests/testthat/test-mask-raster-exact.R), [independent output decoder](../tests/qualification/mask-raster-exports.py) |
| A22, A31 | T09 reviewed | [Export contracts](../tests/testthat/test-export-contract.R), [native QuPath and exact keys](../tests/testthat/test-qupath-native.R), [consumer qualification](../tests/qualification/qupath-roundtrip.R) |
| A33 | T09b reviewed | [Exact provenance regressions](../tests/testthat/test-provenance-keys.R), [443-check final run](evidence/implementation-2026-09-10/t09b/fix1/t09b-fix1-final-green.log), [original probe](evidence/implementation-2026-09-10/metadata-key-observed.json) |
| A24–A25 | T10/T11 reviewed; full app journeys pass | [Widget tests](../tests/audit/widget.test.js), [actual browser runner](../tests/browser/widget.cjs), [overlay fix evidence](evidence/implementation-2026-09-10/t10-fix1/t10-widget.json) |

The T13 independent analytical checks pass, including explicit finite-sample policy, units, calibrated area and label/instance/bitfield agreement. The reference cube also reproduces an RGB normalization error with nonfinite samples; T16 owns that display correction, while raw samples remain preserved.
