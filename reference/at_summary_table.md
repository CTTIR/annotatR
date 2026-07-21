# Session summary statistics

Session summary statistics

## Usage

``` r
at_summary_table(
  session,
  by = c("image", "label", "layer"),
  call = rlang::caller_env()
)
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- by:

  Grouping: `"image"`, `"label"`, or `"layer"`.

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with the grouping key plus `n_rois`, `total_area_px`, `mean_area`, and
`sd_area`. A 0-row tibble when there are no ROIs.

## See also

Other batch:
[`at_batch_apply()`](https://cttir.github.io/annotatR/reference/at_batch_apply.md),
[`at_batch_check_geometry()`](https://cttir.github.io/annotatR/reference/at_batch_check_geometry.md),
[`at_export_all()`](https://cttir.github.io/annotatR/reference/at_export_all.md)
