# ROI area

ROI area

## Usage

``` r
at_roi_area(
  roi,
  level = 0L,
  units = c("px", "physical"),
  call = rlang::caller_env()
)
```

## Arguments

- roi:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- level:

  Integer pyramid level at which to express the area. Default `0`.

- units:

  Either `"px"` (pixels squared, the default) or `"physical"`. Physical
  units require a `pixel_size` attribute on the ROI.

- call:

  The calling environment, for error reporting.

## Value

A numeric scalar area, or `NA_real_` for non-areal geometry (points,
lines).

## See also

Other rois:
[`at_roi_bbox()`](https://cttir.github.io/annotatR/reference/at_roi_bbox.md),
[`at_roi_centroid()`](https://cttir.github.io/annotatR/reference/at_roi_centroid.md),
[`at_roi_circle()`](https://cttir.github.io/annotatR/reference/at_roi_circle.md),
[`at_roi_ellipse()`](https://cttir.github.io/annotatR/reference/at_roi_ellipse.md),
[`at_roi_freehand()`](https://cttir.github.io/annotatR/reference/at_roi_freehand.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_roi_from_sf()`](https://cttir.github.io/annotatR/reference/at_roi_from_sf.md),
[`at_roi_point()`](https://cttir.github.io/annotatR/reference/at_roi_point.md),
[`at_roi_polygon()`](https://cttir.github.io/annotatR/reference/at_roi_polygon.md),
[`at_roi_rect()`](https://cttir.github.io/annotatR/reference/at_roi_rect.md)

## Examples

``` r
at_roi_area(at_roi_rect(0, 0, 10, 5, label = "a"))
#> [1] 50
```
