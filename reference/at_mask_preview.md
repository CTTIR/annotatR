# Downsampled preview of a mask

Nearest-neighbour downsample only (interpolating a label mask would
invent labels that do not exist).

## Usage

``` r
at_mask_preview(mask, max_dim = 1024L, call = rlang::caller_env())
```

## Arguments

- mask:

  An `annot_mask`.

- max_dim:

  Integer maximum dimension of the preview. Default `1024`.

- call:

  The calling environment, for error reporting.

## Value

A downsampled `annot_mask` with the legend pixel counts recomputed.

## See also

Other masks:
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_legend()`](https://cttir.github.io/annotatR/reference/at_mask_legend.md),
[`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/annotatR/reference/at_write_masks.md)
