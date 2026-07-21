# Per-value statistics of a mask

Per-value statistics of a mask

## Usage

``` r
at_mask_stats(mask, pixel_size = NULL, call = rlang::caller_env())
```

## Arguments

- mask:

  An `annot_mask`.

- pixel_size:

  Optional numeric `c(x, y)` physical pixel size for physical area. When
  `NULL`, `area_physical` is `NA`.

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with one row per mask value: `value`, `label`, `n_px`, `area_px`,
`area_physical`, `frac_total`, bounding box (`bbox_xmin`, `bbox_ymin`,
`bbox_xmax`, `bbox_ymax`), and centroid (`centroid_x`, `centroid_y`). A
0-row tibble when the mask is empty.

## See also

Other masks:
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_legend()`](https://cttir.github.io/annotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/annotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/annotatR/reference/at_write_masks.md)

## Examples

``` r
at_mask_stats(at_mask(at_example_project(), "labelled"))
#> # A tibble: 3 × 12
#>   value label     n_px area_px area_physical frac_total bbox_xmin bbox_ymin
#>   <int> <chr>    <int>   <dbl>         <dbl>      <dbl>     <dbl>     <dbl>
#> 1     1 tumour   19600   19600            NA     0.0748       120       150
#> 2     2 necrosis 72704   72704            NA     0.277          0       370
#> 3     3 stroma   34200   34200            NA     0.130        300        30
#> # ℹ 4 more variables: bbox_xmax <dbl>, bbox_ymax <dbl>, centroid_x <dbl>,
#> #   centroid_y <dbl>
```
