# Batch-write the masks of a project

Batch-write the masks of a project

## Usage

``` r
at_write_masks(
  project,
  dir,
  per = c("layer", "roi", "class", "project"),
  type = c("labelled", "binary", "multiclass"),
  level = 0L,
  overwrite = FALSE,
  call = rlang::caller_env()
)
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- dir:

  Output directory (created if needed).

- per:

  One of `"layer"`, `"roi"`, `"class"`, or `"project"`; controls how
  masks are split into files.

- type:

  Mask type passed to
  [`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md).

- level:

  Integer pyramid level. Default `0`.

- overwrite:

  Logical; overwrite existing files. Default `FALSE`.

- call:

  The calling environment, for error reporting.

## Value

An invisible export-receipt
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `path`, `type`, `n_px`, and `bytes`.

## See also

Other masks:
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_agreement()`](https://cttir.github.io/annotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/annotatR/reference/at_mask_derive.md),
[`at_mask_legend()`](https://cttir.github.io/annotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/annotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
[`at_read_npy()`](https://cttir.github.io/annotatR/reference/at_read_npy.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_write_npy()`](https://cttir.github.io/annotatR/reference/at_write_npy.md)
