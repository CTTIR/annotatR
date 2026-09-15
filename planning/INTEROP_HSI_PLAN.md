# annotatR × qupflowR: interop, control, HSI and training — plan, contract record and handoff

Status (2026-09-15): **implemented, checked and handed off locally; not committed.** Governing spec:
the partner prompt `ANNOTATR_PARTNER_BUILD.md` (copy in
`/data/GitHub/CTTIR/public/qupflowR/setup/qupathr-build-kit/prompts/`). Consumer
contract: `docs/22_ANNOTATR_INTEROP.md`, `docs/23_HSI_AND_NAMING.md`,
`docs/14_WORKFLOW_BUNDLES.md`, `docs/06_PROTOCOL.md`, `docs/07_DATA_MODEL.md` and
`adr/005_ANNOTATR_INTEROP.md` in the same kit.

## 1. Source state

| Item | Value |
|---|---|
| HEAD | `f69bf201f651c845ab496f76e25638bc919d4b13` (main, up to date with origin at start) |
| Dirty state before this work | `M .Rbuildignore` (adds `^planning$`), `?? planning/` — user changes, kept |
| Dirty state now | uncommitted working-tree changes only (section 9); git index untouched; no commits, tags or pushes |
| Package version | 0.1.0 → **0.2.0** (DESCRIPTION only; CITATION.cff, .zenodo.json and the DOI untouched) |
| Runtime | R 4.6.1, Linux x86_64 (Ubuntu 26.04), shiny 1.14.0, httpuv 1.6.17, later 1.4.8, curl 7.1.0, callr 3.8.0, shinytest2 0.5.1, chromote 0.5.1, covr 3.6.5, lintr 3.4.0 |
| Baseline tests (HEAD) | 287 tests, 711 passing expectations, 1 skip, 0 failures |

## 2. Decisions

| ID | Decision | Source |
|---|---|---|
| D1 | Consumer name **qupflowR**; handoff functions `at_export_qupflowr()`, `at_import_qupflowr()`, `at_stage_qupflowr()`, `at_commit_qupflowr()`; contract field `consumer: "qupflowR"` | user, 2026-09-14 |
| D2 | Version 0.2.0 (the kit gates I2/I3 on annotatR >= 0.2); citation metadata untouched | user, 2026-09-14 |
| D3 | Classified conditions `at_*_error` (validation, capability, conflict, io, protocol, auth, limit) with parent `at_error` and a `code`; argument validators raise `at_validation_error` | CTTIR Q04 |
| D4 | Handoff digest = SHA-256 of canonical `integrity.json` (sorted keys, no whitespace, integer sizes, no trailing newline) = qupflowR `bundle_digest` rule; checked against Python reference vectors | kit docs/14 |
| D5 | SHA-256 via `tools::sha256sum()` (R >= 4.5.0) with `digest` fallback (Suggests) | R NEWS |
| D6 | I0/I1 `supported` (I0 qualified with QuPath 0.7.0 fixtures); I2/I3 `planned` (implemented, locally tested) until a real qupflowR client run is recorded in `.qualified_clients`; `unavailable` without runtime packages | prompt |
| D7 | All Shiny code in `R/app-*.R`; `at_app()` returns a `shiny.appobj`; `at_annotate()` delegates; `inst/shiny/annotatR/app.R` is a thin wrapper; `www/` served via `addResourcePath("annotatR-www")` | prompt B1, kit Q05 |
| D8 | Control service in-process on httpuv/later; one dispatcher for HTTP and in-process handles; tokens in a package-private registry, never in handles, manifests, logs or RDS | design |
| D9 | `state_revision` increments on every accepted state change; `annotation_revision` (`sha256:`) follows annotation content only; mutations require `expected_revision == state_revision` | kit docs/22 |
| D10 | QuPath GeoJSON writer defaults to the QuPath 0.4+ dialect with deterministic UUIDs and annotatR ids in `properties.metadata`; `dialect = "legacy"` keeps the 0.1 form | QuPath 0.7.0 evidence |
| D11 | Browser lane opt-in via `ANNOTATR_BROWSER_TESTS=true`; hosts that block Chromium's user-namespace sandbox set `ANNOTATR_CHROME_NO_SANDBOX=true` (local test app only) | Ubuntu 26.04 AppArmor |
| D12 | Build and check from a clean export (`git ls-files -co --exclude-standard`), never from the working directory: R copies git-ignored `hsi-workbench/` (54 GB) before applying `.Rbuildignore`, which exceeded the /tmp quota | observed 2026-09-15 |

## 3. Contract versions

| Identifier | Version | Where |
|---|---|---|
| `annotatr-capabilities-v1` | 1.0 | `at_interop_capabilities()` |
| `annotatr-handoff-v1` (manifest, integrity, training manifest) | 1.0 | `inst/schema/annotatr-handoff-v1/` |
| integrity `format_version` | 1.0 | `integrity.json` |
| `annotatr-control-v1` | 1.0 | `inst/schema/annotatr-control-v1/` (command, response, event, events-page, handshake, health, state, request-record) |
| `annotatr-training-v1` | 1.0 | `training-manifest.json` |
| `annotatr-hsi-v1` | 1.0 | `hsi_manifest.json`, `inst/schema/annotatr-hsi-v1/tivita-profile.schema.json` |
| TIVITA default profile | `tivita_640x480x100_v1` | `at_tivita_profile()` |
| Fixture version | 2026.09.14 | `tests/testthat/fixtures/` |

Readers reject an unknown major version (`PROTOCOL_MISMATCH`); unknown optional data is
accepted only under `extensions` and preserved (control request records keep it).

## 4. Public surface added in 0.2.0

- Interop: `at_interop_capabilities()`, `at_interop_manifest()`, `at_annotation_revision()`,
  `at_export_qupflowr()`, `at_import_qupflowr()`, `at_stage_qupflowr()`, `at_commit_qupflowr()`.
- App/control: `at_app()`, `at_control_capabilities()`, `at_control_start()`, `at_control_stop()`,
  `at_control_close()`, `at_control_connect()`, `at_control_state()`, `at_control_events()`,
  `at_control_command()`, `at_control_request_status()`, `at_canvas_set_selection()`.
- HSI: `at_hsi_meta()`, `at_convert_values()`, `at_band_operations()`, `at_band_view()`,
  `at_read_stats()`, `at_tivita_profile()`, `at_cubert_export_envi()`; `at_bands()` gains
  `fwhm`, `order` and `wavelength_status`.
- Training: `at_training_export()`, `at_training_check()`, `at_training_import()`.

Control endpoints (`/v1`): GET `health`, `handshake`, `capabilities`, `state`,
`events?after=&limit=`, `requests/{request_id}`; POST `session/load`, `session/save`,
`context/goto`, `context/view`, `context/selection`, `annotations/stage`,
`annotations/commit`, `mask/preview`, `export`, `training/export`, `close`. Every other
path, including `/eval`, returns 404.

## 5. Security boundaries

- Nothing listens unless `at_control_start(control = "loopback")` is called; host must be
  `127.0.0.1`; port 0 picks a random port.
- Random 256-bit bearer token with TTL 1 s–24 h (default 900 s); an expired token → 401
  `TOKEN_EXPIRED` and the listener stops (manifest state `expired`).
- Token only in memory or in a new owner-only (0600) `token_file`; never in URLs, the
  lifecycle manifest, logs, downloads or serialised handles.
- `Origin` header → 403; Host must be `127.0.0.1:<port>` or `localhost:<port>`; body
  > 1 MiB → 413; non-JSON → 415.
- Payload references and outputs resolve only below the negotiated root; absolute paths,
  `..` and symlink escapes → `PATH_OUTSIDE_ROOT`; output names are simple safe names.
- Typed operations only: no R/shell/Python evaluation, no DOM control, no QuPath project
  writes. `at_control_stop()` works only in the owning process; `at_control_close()` on a
  remote handle closes only that service; no process is ever killed.
- Handoff import verifies the SHA-256 inventory, schema and ids before returning objects
  and refuses RDS. I2 is not an OS sandbox; local OS permissions still apply.

## 6. Migration

- Existing 0.1 projects, sessions and masks load unchanged; sessions saved by the app
  already stripped image handles and reopen images from their paths.
- `at_write_qupath()` default output changed to the QuPath 0.4+ dialect; use
  `dialect = "legacy"` for consumers of the 0.1 `object_type`/`colorRGB` form. Both are read.
- `at_bands()` has three appended columns; the first four are unchanged.
- ENVI files with inconsistent headers now fail with a coded error instead of returning
  recycled or offset-shifted pixels; bare TIVITA cubes need a matching profile or sidecar.
- Code that sourced `inst/shiny/annotatR/modules` or set `options(annotatR.session)` should
  call `at_app()`; the compatibility `app.R` still honours the option.

## 7. Findings fixed on the way

- The Cubert backend called a non-existent `cuvis.r` API → rewritten against cuvis.r 0.1.0 / CUVIS SDK 3.5.3.
- ENVI `header offset` ignored (A10) and short payloads recycled (A13) → validated.
- Numeric choice arguments (`bits = 8L`, `connectivity = 4L`) rejected (A14) → fixed.
- App navigation lost unsaved edits or stored projects in the wrong slot (A02/A12) → the
  current project is kept in its own queue entry before switching.
- App export file names were unsanitised (A22, app path) → safe unique stems.
- Polygon holes selected the enclosing polygon (A24) and MultiPolygons did not render →
  hole-aware hit testing and multipart rendering in the canvas.
- GeoJSON coordinates lost precision (15 significant digits) → 17.
- An empty app export receipt crashed the download (`attr<-` on `NULL`) → empty data frame.
- Non-ASCII glyphs in app strings (R CMD check WARNING after the move to `R/`) → `\u` escapes.
- `R CMD build` would have shipped `inst/shiny/annotatR/hsi-workbench/` (data derived from
  real SpecCubes) → build-ignored; the files themselves were not touched.

## 8. Evidence

Logs, commands and exit codes: `planning/evidence/2026-09-15/README.md`. Summary:

| Lane | Result |
|---|---|
| Full suite, `NOT_CRAN=true devtools::test()` | exit 0 — 54 files, 381 tests, 1647 passing expectations, 0 failures/errors/warnings; 2 named skips (Cubert real-data lane without `ANNOTATR_CUVIS_FIXTURE`; the "no cuvis.r" error path because cuvis.r is installed) |
| Loopback HTTP lane (`test-control-http.R`, callr child) | exit 0 — 2 tests, 30 expectations (re-run after the child-loader fix, see below) |
| Browser lane (shinytest2 + Chromium) | exit 0 — 3 journeys, 22 expectations |
| Cubert SDK + TIVITA real-data lane | passed (CUVIS SDK 3.5.3, cuvis.r 0.1.0; data stay local, only digests recorded) |
| QuPath 0.7.0 interchange | QuPath reads annotatR 0.2 output keeping UUIDs, classes, metadata and holes; annotatR reads QuPath-written objects (`data-raw/qupath-fixtures/provenance.md`) |
| Canonical JSON digests | equal to the Python reference vectors |
| `R CMD check --as-cran` (clean export) | `Status: 1 ERROR` — only CRAN incoming *conflicting package names* (annotatR vs Bioconductor annotatr); tests (16 min) and vignettes OK; 0 WARNINGs, 0 NOTEs |
| Tests-only coverage (`covr`, `NOT_CRAN=true`) | exit 0 — **88.87 %** (HEAD baseline 87.12 %, when the Shiny modules in `inst/` were not counted); lowest: `R/zzz.R` 0 %, `R/backend-cuvis.R` 21.5 % (SDK lane needs `ANNOTATR_CUVIS_FIXTURE`), `R/backend-tiff.R` 48 % |
| pkgdown site | exit 0 |
| House lint | 3 findings, all the pre-existing `verbose` argument of `at_fix_geometry()`; 0 in new code |
| `git diff --check` | exit 0 |

The first coverage run failed in `test-control-http.R`: under covr the tests run from the
installed copy, whose `R/` directory holds no `.R` sources, so the callr child tried
`pkgload::load_all()` on an installed package. The child loader now requires `.R` sources
before a development load, and a child that dies early reports its stderr.

## 9. Handoff

**Source revision.** `f69bf201f651c845ab496f76e25638bc919d4b13` on `main`; all work is
uncommitted in the working tree (git index untouched; no commits, tags, pushes or releases).

**Dirty state.** 63 modified and 14 deleted tracked files (77 files, +1502/−1526 lines
tracked diff), plus new untracked files: 17 `R/` files, 12 schemas under `inst/schema/`,
28 `man/` pages, 16 test files, fixtures under `tests/testthat/fixtures/{interop,qupath-0.7.0}/`,
`data-raw/{interop,qupath}-fixtures/`, `vignettes/partner-interop.Rmd` and this `planning/`
record. The user's pre-existing changes (`^planning$` in `.Rbuildignore`, `planning/`) are
kept. `inst/shiny/annotatR/hsi-workbench/` (git-ignored, local) was not touched.

**Commands and exit codes** (details in the evidence README):

| Command | Exit |
|---|---|
| `NOT_CRAN=true Rscript -e 'devtools::test()'` | 0 |
| `NOT_CRAN=true Rscript -e 'devtools::test(filter = "control-http")'` | 0 |
| browser lane (`ANNOTATR_BROWSER_TESTS=true ANNOTATR_CHROME_NO_SANDBOX=true`, `filter = "app-browser"`) | 0 |
| `ANNOTATR_CUVIS_FIXTURE=<local .cu3s> ... filter = "cuvis-sdk\|backend-tivita"` | 0 |
| `R CMD build --no-manual <clean export>` | 0 |
| `_R_CHECK_FORCE_SUGGESTS_=false R CMD check --as-cran --no-manual annotatR_0.2.0.tar.gz` | 1 (the name-conflict ERROR only) |
| `NOT_CRAN=true covr::package_coverage(<clean export>, type = "tests")` | 0 |
| `pkgdown::build_site(<clean export>)` | 0 |
| house lint (`lint-cttir.R`) | 0 |
| `git diff --check` | 0 |

**Artefacts.** `annotatR_0.2.0.tar.gz`, 3,692,862 bytes, SHA-256
`7f79f194a960102504c1a8c422e84b56fb4d6c2d345849a71969807d2ea04543` (358 entries; no
`hsi-workbench`, `planning` or `data-raw`). Built in a scratch directory that was removed
afterwards; rebuild with the clean-export procedure (D12). `R CMD build` stamps the build
time, so a rebuild has a different digest.

**Open dependencies.**

1. I2 (direct control) and I3 (live sync) stay `planned` until a real qupflowR client has run
   against `at_control_start()`/`at_export_qupflowr()`; then add the run to
   `.qualified_clients` in `R/interop-capabilities.R` with its evidence.
2. The qupflowR build kit still says qupathR; the consumer side has to adopt
   `consumer: "qupflowR"` and the function names from D1.
3. CRAN incoming reports a name conflict with Bioconductor `annotatr` (the only check
   ERROR, independent of this work): rename or skip CRAN — user decision.
4. Browser lane needs Chromium; on Ubuntu 26.04 also `ANNOTATR_CHROME_NO_SANDBOX=true`.
5. Cubert lane needs the CUVIS SDK and a permitted local `.cu3s`; not reproducible in CI.
6. RBioFormats is not installed here, so the Bio-Formats backend was not exercised.
7. House lint wants `quiet` instead of `verbose` in `at_fix_geometry()` (API change, deferred).
8. `tests/testthat/_problems/` (5 tracked files from HEAD) ships in the tarball; remove or
   build-ignore — user decision.

**Next step.** Review the diff, commit it on a feature branch, then run the qupflowR
client against a loopback service and a handoff directory to qualify I2/I3 (item 1).
