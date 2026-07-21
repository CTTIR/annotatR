# Stack per-layer masks into a 3D array

Stack per-layer masks into a 3D array

## Usage

``` r
at_mask_stack(project, layers = NULL, level = 0L, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- layers:

  Optional layer name(s) to include; all by default.

- level:

  Integer pyramid level. Default `0`.

- call:

  The calling environment, for error reporting.

## Value

A 3D integer array `[y, x, layer]`, one multi-class plane per layer; the
third dimension is named by layer.

## See also

Other masks:
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_agreement()`](https://cttir.github.io/annotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/annotatR/reference/at_mask_derive.md),
[`at_mask_legend()`](https://cttir.github.io/annotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/annotatR/reference/at_mask_preview.md),
[`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
[`at_read_npy()`](https://cttir.github.io/annotatR/reference/at_read_npy.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/annotatR/reference/at_write_masks.md),
[`at_write_npy()`](https://cttir.github.io/annotatR/reference/at_write_npy.md)
