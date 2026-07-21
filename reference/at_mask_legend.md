# Legend of a mask

Legend of a mask

## Usage

``` r
at_mask_legend(mask, call = rlang::caller_env())
```

## Arguments

- mask:

  An `annot_mask`.

- call:

  The calling environment, for error reporting.

## Value

The mask's legend
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
(`value`, `label`, `layer`, `roi_id`, `n_px`, `colour`).

## See also

Other masks:
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_preview()`](https://cttir.github.io/annotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/annotatR/reference/at_write_masks.md)

## Examples

``` r
at_mask_legend(at_mask(at_example_project(), "labelled"))
#> # A tibble: 3 × 6
#>   value label    layer   roi_id         n_px colour 
#>   <int> <chr>    <chr>   <chr>         <int> <chr>  
#> 1     1 tumour   regions roi_000000017 19600 #999999
#> 2     2 necrosis regions roi_000000018 72704 #E69F00
#> 3     3 stroma   regions roi_000000019 34200 #56B4E9
```
