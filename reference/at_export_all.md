# Export a whole session

Export every selected image's annotations in the requested formats,
isolating per-image failures so one bad image never aborts the run.

## Usage

``` r
at_export_all(
  session,
  dir,
  formats = c("mask_tiff", "geojson", "qupath", "rds", "csv"),
  scope = c("complete", "all", "current", "flagged"),
  mask_type = c("labelled", "binary", "multiclass"),
  level = 0L,
  overwrite = FALSE,
  progress = TRUE,
  call = rlang::caller_env()
)
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- dir:

  Output directory (created if needed).

- formats:

  Any of `"mask_tiff"`, `"geojson"`, `"qupath"`, `"rds"`, `"csv"`.

- scope:

  `"complete"` (default), `"all"`, `"current"`, or `"flagged"`.

- mask_type:

  Mask type for `"mask_tiff"`.

- level:

  Integer pyramid level. Default `0`.

- overwrite:

  Logical; overwrite existing files. Default `FALSE`.

- progress:

  Logical; show a progress bar. Default `TRUE`.

- call:

  The calling environment, for error reporting.

## Value

An invisible export-receipt
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `image`, `format`, `path`, `bytes`, `n_rois`, `status`, and
`message`. Also written to `_export_manifest.csv` alongside the exports.

## See also

[`at_write_masks()`](https://cttir.github.io/annotatR/reference/at_write_masks.md),
[`at_manifest()`](https://cttir.github.io/annotatR/reference/at_manifest.md)

Other batch:
[`at_batch_apply()`](https://cttir.github.io/annotatR/reference/at_batch_apply.md),
[`at_batch_check_geometry()`](https://cttir.github.io/annotatR/reference/at_batch_check_geometry.md),
[`at_summary_table()`](https://cttir.github.io/annotatR/reference/at_summary_table.md)

## Examples

``` r
sess <- at_example_session(2)
dir <- file.path(tempdir(), "annotatR-export")
at_export_all(sess, dir, formats = "geojson", scope = "all", progress = FALSE)
```
