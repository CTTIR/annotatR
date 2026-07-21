# Extract summary statistics under ROIs

Compute per-band summary statistics of image values inside each ROI.
Works tile-wise and never materialises the whole image.

## Usage

``` r
at_extract(
  project,
  img = NULL,
  stat = "mean",
  layer = NULL,
  label = NULL,
  level = 0L,
  bands = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- img:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md);
  defaults to the project's image.

- stat:

  One or more of `"mean"`, `"median"`, `"sd"`, `"min"`, `"max"`,
  `"sum"`, `"n"`, or `"all"` (every statistic).

- layer, label:

  Optional filters.

- level:

  Integer pyramid level. Default `0`.

- bands:

  Optional band indices; all bands by default.

- call:

  The calling environment, for error reporting.

## Value

A long
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `roi_id`, `layer`, `label`, `band` (integer), `band_name`,
`wavelength` (`NA` when not spectral), `stat`, `value`, and `n_px`. A
0-row tibble with these columns when nothing matches.

## See also

[`at_extract_spectrum()`](https://cttir.github.io/annotatR/reference/at_extract_spectrum.md),
[`at_extract_pixels()`](https://cttir.github.io/annotatR/reference/at_extract_pixels.md)

Other extraction:
[`at_extract_pixels()`](https://cttir.github.io/annotatR/reference/at_extract_pixels.md),
[`at_extract_spectrum()`](https://cttir.github.io/annotatR/reference/at_extract_spectrum.md)

## Examples

``` r
proj <- at_example_project()
at_extract(proj, stat = "mean")
#> # A tibble: 9 × 9
#>   roi_id        layer   label     band band_name wavelength stat  value  n_px
#>   <chr>         <chr>   <chr>    <int> <chr>          <dbl> <chr> <dbl> <int>
#> 1 roi_000000008 regions tumour       1 R                 NA mean   109. 19600
#> 2 roi_000000008 regions tumour       2 G                 NA mean   109. 19600
#> 3 roi_000000008 regions tumour       3 B                 NA mean   109. 19600
#> 4 roi_000000009 regions necrosis     1 R                 NA mean   138. 72704
#> 5 roi_000000009 regions necrosis     2 G                 NA mean   138. 72704
#> 6 roi_000000009 regions necrosis     3 B                 NA mean   138. 72704
#> 7 roi_000000010 regions stroma       1 R                 NA mean   139. 34200
#> 8 roi_000000010 regions stroma       2 G                 NA mean   139. 34200
#> 9 roi_000000010 regions stroma       3 B                 NA mean   139. 34200
```
