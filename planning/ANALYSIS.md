# Project analysis and finding register

Prepared 2026-09-10 against `f69bf201f651c845ab496f76e25638bc919d4b13`. Implementation status: **all findings remain open**. This document refines the interpretation of the [historical audit](evidence/2026-09-10/audit.md) and maps its findings into the [roadmap](ROADMAP.md).

## Assessment

annotatR already has useful foundations: an explicit image coordinate convention, a compact ROI/layer/project/session model, a backend registry, substantial test coverage by scenario count, and multiple mask/export workflows. Most planned improvements can build on those interfaces.

The main risk is that different parts of the implementation do not consistently enforce the same contracts. The app can associate a project with the wrong queue entry; persistence strips state without reliably reconstructing it; exporters transform coordinates without updating their coordinate-level metadata; optimized and general rasterizers can disagree. These errors can produce plausible outputs, making visual inspection and a green unit suite insufficient.

Stabilization should therefore concentrate on shared contracts and complete workflows. A broad rewrite would make it harder to attribute output changes and preserve existing annotations. New formats and performance optimizations should follow independently verified correctness fixtures.

## What the evidence establishes

| Evidence | Recorded result | Interpretation |
|---|---|---|
| Existing test suite | 287 cases processed, 710 assertions passed, one skipped case, no failures/errors/warnings | Existing scenarios pass; this is not a measured line/branch coverage percentage |
| Core diagnostics | Incorrect mask coverage, transforms, IDs, reader results, cache identity, and exports | Reproducible failures under the recorded local stack |
| Full Shiny server diagnostics | Cross-image saves/history, stale project on folder load, discarded edits, incorrect saved indicator | Strong server-level evidence; browser event timing and rendering still need direct verification |
| JavaScript harness | Hole click emits erase; a second widget replaces the first widget's effective routing | Focused behavior reproduced in a simulated DOM/message environment |
| Package check | Available-dependency check completed with two NOTEs; examples passed | Package loading and static checks succeeded under the stated options, not a complete release qualification |
| Optional-format coverage | RBioFormats unavailable; proprietary input reads not exercised | No claim of verified OME/Cubert interoperability |
| Performance review | Readers eagerly materialize arrays; current benchmark often starts with arrays already allocated | Structural evidence of an unfulfilled lazy-read contract; no measured real-WSI capacity claim |

The historical audit tracks **25 findings, 10 P1 and 15 P2**, with reproduced primary symptoms. Some findings combine a reproduced symptom with additional source-review observations. In particular, A14's unused connectivity parameter, A20's broader preview implications, and A24's missing MultiPolygon handling need their own direct assertions. A01 simulates a cold resume by clearing the cache; A07 simulates restart by resetting the ID counter. Both need genuine fresh-process fixtures before closure.

For A05, the observed triangle counts of 25 and 13 establish inconsistency. The general rasterizer's value 13 is not independently established as the universal intended boundary result. The documentation specifies axis-aligned half-open ties but needs an unambiguous rule for sloped boundaries. Decide that rule and verify it independently before using either path as the reference.

## Root causes and architectural direction

| Root cause | Evidence | Proposed correction | Practical limit |
|---|---|---|---|
| Identity is inferred from mutable cursor/name/path | A02–A04, A07–A09 | Persist separate queue identity, annotation identity, and source/read identity; verify identity on actions and saves | Canonical paths alone do not detect file replacement or distinct reader options |
| State transitions are spread across observers | A02–A04, A11–A12 | Shared entry-aware mutation/navigation functions, bounded per-entry history, explicit session generation | Observing every session change can introduce reactive reload/save loops |
| Durable state and runtime handles are mixed | A01, A23 | Versioned source descriptors, one reopen path, staged checkpoints, honest dirty/saved state | Not every legacy file records enough information to reconstruct custom reads |
| Coordinate and membership logic is duplicated | A05–A06, A15–A16, A18, A21 | One transform/membership contract used by masking, extraction, plotting, and interchange | Missing pyramid metadata must not be replaced by guessed ratios |
| Masks and binary files lack enforced semantic metadata | A10, A13–A14, A17, A19–A20 | Validate before allocation; preserve encoding, background, units, code maps, dimensions, and schema | Lossless integer arrays do not automatically preserve class meaning |
| UI and exports have weaker boundaries than core objects | A08, A22, A24–A25 | Safe filenames, complete receipts, geometry-aware display/hit-testing, per-instance widget routing | A Node harness does not establish actual browser behavior or accessibility |

The existing S3-style objects and backend registration API can remain. Proposed schema additions should be additive initially. Internal helpers should have one responsibility: transform coordinates, resolve source identity, apply an entry mutation, serialize a checkpoint, or interpret mask membership. Avoid introducing a second competing object hierarchy.

## Complete finding register

IDs A01–A25 retain the numbering in the historical audit. P1 means fix before relying on the affected workflow; P2 is a narrower supported case. Priorities are impact assessments, not security vulnerability scores. Primary work-package assignment is unique; supporting work may span other packages.

| ID | Priority | Finding and observed symptom | Primary package | Evidence file |
|---|---|---|---|---|
| A01 | P1 | Stripped image handle is not reopened; resumed tile has length zero | T03 | reproduce.log |
| A02 | P1 | Shift+Enter stores image 1's project in slot 2 | T02 | reproduce-app.log |
| A03 | P1 | Undo changes the live image while cursor remains on the next entry | T02 | reproduce-app.log |
| A04 | P1 | Loading a folder at cursor 1 changes manifest but retains previous project | T02 | reproduce-app.log |
| A05 | P1 | Triangle coverage changes from 25 to 13 when an unrelated ROI is added | T04 | reproduce.log |
| A06 | P1 | GeoJSON/CSV round trip changes level-zero area 36 to 144 | T05 | reproduce.log |
| A07 | P1 | Restarted ID counter produces IDs 1,2,3,4,3 | T01 | reproduce.log |
| A08 | P1 | Two successful exports share one output path; second label survives | T01 | reproduce.log |
| A09 | P1 | Same relative filename from different directories returns first file's pixels | T01 | reproduce.log |
| A10 | P1 | ENVI header sentinel becomes a pixel because offset is ignored | T07 | reproduce.log |
| A11 | P2 | Undo leaves live count zero, saved count one, and indicator “saved” | T02 | reproduce-app.log |
| A12 | P2 | Next/Previous with autosave off discards a newly drawn ROI | T02 | reproduce-app.log |
| A13 | P2 | Short NPY/ENVI payloads repeat available samples to fill the declared array | T07 | reproduce.log |
| A14 | P2 | Explicit valid integer choices error; connectivity is also unused in source | T08 | reproduce.log |
| A15 | P2 | Integer point covers one mask pixel but produces no extraction row | T04 | reproduce.log |
| A16 | P2 | Difference of physically identical mixed-level squares has area 75 | T05 | reproduce.log |
| A17 | P2 | Binary mask with background 1 silently erases foreground | T06 | reproduce.log |
| A18 | P2 | Downsampled image spans x=1..1024 while ROI remains at x=1800..1900 | T05 | reproduce-extra.log |
| A19 | P2 | RDS mask import changes label “tumour” to “1” | T06 | reproduce-extra.log |
| A20 | P2 | Bitfield legends count 36/36 pixels but statistics count 32/32 | T06 | reproduce-extra.log |
| A21 | P2 | Anisotropic pyramid: project mask covers 72 pixels, per-ROI export 36 | T05 | reproduce-extra.log |
| A22 | P2 | Project name `../escaped` writes outside the selected export directory | T09 | reproduce-extra.log |
| A23 | P2 | Default session path overwrites despite `overwrite=FALSE` | T03 | reproduce-extra.log |
| A24 | P2 | Clicking a polygon hole emits an erase event for the polygon | T10 | reproduce-widget.log |
| A25 | P2 | After creating widget B, widget A's proxy tool command no longer applies | T10 | reproduce-widget.log |

Evidence files are in [evidence/2026-09-10](evidence/2026-09-10/README.md); the [audit record](evidence/2026-09-10/audit.md) contains source references and detailed reproduction explanations. The [finding closure map](IMPLEMENTATION.md#finding-closure-map) records current status, implementation revision state, and regression artifacts separately from this historical register. Do not infer closure from elapsed time, a refactor, or a passing aggregate test count.

## Additional observations requiring qualification

These observations are separate from the 25 findings and should not be presented as measured production incidents.

| ID | Observation | Evidence and uncertainty | Planned response |
|---|---|---|---|
| O01 | Lazy image/large-slide claims exceed the implemented memory discipline | [ENVI reader](../R/backend-envi.R), [TIFF reader](../R/backend-tiff.R), and [memory vignette](../vignettes/images-and-backends.Rmd); no large real-image load test | T15–T17: explicit capabilities, actual windows, bounded working memory, measured envelope |
| O02 | Embedded display requires magick and suppresses decode failures to NULL | [Widget R wrapper](../R/widget-canvas.R), [launcher](../R/at_annotate.R); minimal-dependency browser run outstanding | T11: capability checks and actionable display errors; T16: bounded previews |
| O03 | Most CI behavior is external; coverage floor is zero and lint nonblocking | [Workflow configuration](../.github/workflows/test-coverage.yaml); shared execution not audited | T18: inspect shared contract at implementation time, baseline, then enforce relevant checks |
| O04 | Support/documentation statements diverge from implementation | [DESCRIPTION](../DESCRIPTION) refers to OpenSeadragon; [widget](../inst/htmlwidgets/atcanvas.js) implements a standalone canvas; NEWS headline is 0.0.1 while DESCRIPTION is 0.1.0 | T11/T18: reconcile claims and release notes with shipped behavior |
| O05 | Quantitative semantics need explicit qualification beyond the reproduced bugs | Missing/nonfinite values, calibration units, code-map compatibility, absent classes, bitfield comparison, and sampling units were not fully audited | T12–T14: analytical contracts and independent reference results |
| O06 | Security and deployment scope is incomplete | Targeted source credential-pattern scan only; no complete dependency/history scan or multiuser deployment review | T18: document local versus hosted use and qualify exposed file/data boundaries for the supported deployment mode |

## Implications for quantitative analysis

The failure chain matters. If source identity is wrong, a correctly computed mean describes the wrong image. If mask support is wrong, the wrong pixels enter that mean. If class codes differ between files, apparently valid agreement statistics compare different labels. If physical pixel sizes or wavelengths are unknown, numeric output alone does not establish calibrated area or spectral meaning.

Use this dependency order: **source identity → coordinate/grid fidelity → class/bitfield semantics → pixel extraction → aggregation/comparison → reporting and interpretation**. Validate each stage with an independent fixture before adding analytical convenience features.

Keep display normalization separate from stored raw values. Record invalid and excluded counts alongside means and spectra. Represent calibration and units explicitly instead of treating `px` as a physical length. For agreement, distinguish categorical class comparison from instance matching and bitfield membership. Aggregate at declared units; pixels from one image should not silently stand in for independent images in uncertainty calculations.

These are proposed software/analysis contracts. Domain-specific thresholds, calibration models, and study designs require the relevant data owner's specification; they are not established by the package audit.

## How to improve future audits

1. Define the reviewed revision and support configuration before collecting results. Separate source checks, executed scenarios, cross-process checks, browser checks, and external-format checks.
2. Record exact reproductions and failure signals. Convert diagnostic prints into assertions with explicit expected outcomes and a failing-before revision.
3. Use independent oracles. Round-tripping through two functions from the same package can preserve the same bug; add hand-computed matrices and externally written fixtures.
4. Exercise complete user journeys and adversarial transitions, including failed saves, queue replacement, multiple widgets, and stale events. Module isolation remains useful but cannot replace these tests.
5. Report skipped capabilities and uncertainty alongside successes. Do not replace absent measurements with a coverage percentage, speed claim, or blanket “secure” statement.
6. Measure performance from process start with cold/warm cases, input sizes, versions, and hardware recorded. Compare equal workloads; the current rectangle-versus-near-rectangle timing does not independently establish optimization correctness.
7. Close each finding with a specific regression and observed result, then check neighboring invariants. Repeat broad audits after material architecture/schema changes, not after every documentation edit.

The [validation strategy](VALIDATION.md) translates these principles into concrete mandatory checks, optional capability checks, and release evidence.
