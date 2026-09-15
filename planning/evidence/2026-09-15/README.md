# Evidence 2026-09-15 — annotatR 0.2.0 partner build (uncommitted working tree on f69bf20)

Machine: Linux x86_64, Ubuntu 26.04, R 4.6.1, 72 cores (shared; load average about 30 during runs).
All runs used the working tree described in `planning/INTEROP_HSI_PLAN.md` section 1.

| File | Command (from the package root unless noted) | Result |
|---|---|---|
| `tests-full.log` | `NOT_CRAN=true Rscript -e 'devtools::test()'` (ListReporter) | exit 0 — 54 files, 381 tests, 1647 passing expectations, 0 failures, 0 errors, 0 warnings, 2 skips with named prerequisites |
| `tests-control-http.log` | `NOT_CRAN=true Rscript -e 'devtools::test(filter = "control-http")'` (after the child-loader fix; `tests-full.log` predates that helper-only change) | exit 0 — 2 tests, 30 passing expectations |
| `tests-browser.log` | `NOT_CRAN=true CHROMOTE_CHROME=~/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome ANNOTATR_BROWSER_TESTS=true ANNOTATR_CHROME_NO_SANDBOX=true Rscript -e 'devtools::test(filter = "app-browser")'` | exit 0 — 3 journeys, 22 passing expectations |
| `lane-cubert-tivita-realdata.log`, `lane-cubert-summary.txt` | `ANNOTATR_CUVIS_FIXTURE=<local .cu3s> Rscript -e 'devtools::test(filter = "cuvis-sdk|backend-tivita")'` | passed; CUVIS SDK 3.5.3 / cuvis.r 0.1.0; 1080 x 1000 px, 61 bands, 430–910 nm, reflectance; the SDK prints a spurious `sleep: invalid time interval` message; the TIVITA workbench integration test read a real 640 x 480 x 100 cube |
| `rcmdcheck-driver.log`, `rcmdcheck-00check.log`, `tarball-contents.txt` | clean export via `git ls-files -co --exclude-standard`, then `R CMD build --no-manual` and `_R_CHECK_FORCE_SUGGESTS_=false R CMD check --as-cran --no-manual` | build exit 0; check exit 1, `Status: 1 ERROR` — only *CRAN incoming feasibility: conflicting package names (annotatR vs Bioconductor annotatr)*, which depends on the package name alone; tests and vignettes OK; 0 WARNINGs, 0 NOTEs |
| `coverage-tests-only.log` | `NOT_CRAN=true covr::package_coverage(<clean export>, type = "tests")` | exit 0 — 88.87 % of lines; per-file table in the log (lowest: `R/zzz.R` 0 %, `R/backend-cuvis.R` 21.5 % because the SDK lane is not part of this run, `R/backend-tiff.R` 48 %). A first run failed in `test-control-http.R` (callr child tried `load_all()` on the installed copy); fixed and re-run |
| `pkgdown.log` | `pkgdown::build_site(<clean export>, override = list(destination = <scratch>/site))` | exit 0 — site built to the session scratch directory (not kept) |
| `lint-house.log` | CTTIR house linters (`/data/GitHub/CTTIR/public/.github/config/lint-cttir.R`) via `lintr::lint_package()` | 3 findings, all the pre-existing `verbose` argument of `at_fix_geometry()` (API name kept); 0 in new code |
| `git-diff-check.log` | `git diff --check` | exit 0 |

Tarball `annotatR_0.2.0.tar.gz` (3,692,862 bytes, 358 entries) SHA-256
`7f79f194a960102504c1a8c422e84b56fb4d6c2d345849a71969807d2ea04543`; contains no
`hsi-workbench`, `planning` or `data-raw` content. It was rebuilt and re-checked after the
final test change; the earlier tarball (`9fd8624f…`) is superseded.

Independent interchange evidence lives with the fixtures: QuPath 0.7.0 scripts, commands,
exit codes and hashes in `data-raw/qupath-fixtures/provenance.md`; Python canonical-JSON
digest vectors in `data-raw/interop-fixtures/make_canonical_vectors.py`.

HEAD baseline coverage for comparison (`git archive HEAD`, same command):
87.12 % — note that at HEAD the Shiny modules lived in `inst/` and were not counted.
