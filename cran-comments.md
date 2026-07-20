## R CMD check results

0 errors | 0 warnings | 0 notes

## Test environments

* local: Ubuntu 24.04 (noble), R 4.6.1
* GitHub Actions:
  * ubuntu-latest (R-devel, R-release, R-oldrel-1)
  * macos-latest (R-release)
  * windows-latest (R-release)

## Notes

There are no notes. All optional (`Suggests`) packages are guarded with
`requireNamespace()`, so the package builds, checks, and loads with none of them
installed; the heavy `Imports` (`sf`, `stars`) are used throughout the core.

## Submission

This is a development release (0.0.1). It is not yet submitted to CRAN.
