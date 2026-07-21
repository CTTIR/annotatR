# A populated example project

A populated example project

## Usage

``` r
at_example_project(call = rlang::caller_env())
```

## Arguments

- call:

  The calling environment, for error reporting.

## Value

An
[annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
over the tissue example with one layer of three labelled regions.

## See also

Other example data:
[`at_example_image()`](https://cttir.github.io/annotatR/reference/at_example_image.md),
[`at_example_path()`](https://cttir.github.io/annotatR/reference/at_example_path.md),
[`at_example_session()`](https://cttir.github.io/annotatR/reference/at_example_session.md)

Other projects:
[`at_add_layer()`](https://cttir.github.io/annotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/annotatR/reference/at_add_roi.md),
[`at_layers()`](https://cttir.github.io/annotatR/reference/at_layers.md),
[`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md),
[`at_remove_layer()`](https://cttir.github.io/annotatR/reference/at_remove_layer.md),
[`at_remove_roi()`](https://cttir.github.io/annotatR/reference/at_remove_roi.md),
[`at_rois()`](https://cttir.github.io/annotatR/reference/at_rois.md),
[`at_summary()`](https://cttir.github.io/annotatR/reference/at_summary.md),
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)

## Examples

``` r
proj <- at_example_project()
at_rois(proj)
#> # A tibble: 3 × 14
#>   roi_id    layer label geom_type level area_px centroid_x centroid_y n_vertices
#>   <chr>     <chr> <chr> <chr>     <int>   <dbl>      <dbl>      <dbl>      <int>
#> 1 roi_0000… regi… tumo… POLYGON       0   19600        190        220          5
#> 2 roi_0000… regi… necr… POLYGON       0   72704        256        441          5
#> 3 roi_0000… regi… stro… POLYGON       0   34200        390        125          5
#> # ℹ 5 more variables: created <dttm>, modified <dttm>, author <chr>,
#> #   source <chr>, geometry <POLYGON>
```
