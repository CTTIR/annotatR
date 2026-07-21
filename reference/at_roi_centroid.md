# ROI centroid

ROI centroid

## Usage

``` r
at_roi_centroid(roi, call = rlang::caller_env())
```

## Arguments

- roi:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A numeric vector `c(x, y)` in the ROI's stored coordinates (at its own
`level`).

## See also

Other rois:
[`at_roi_area()`](https://cttir.github.io/annotatR/reference/at_roi_area.md),
[`at_roi_bbox()`](https://cttir.github.io/annotatR/reference/at_roi_bbox.md),
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
at_roi_centroid(at_roi_rect(0, 0, 10, 10, label = "a"))
#> [1] 5 5
```
