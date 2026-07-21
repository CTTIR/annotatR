# Create a freehand ROI

A freehand trace is stored as a closed polygon, optionally simplified.

## Usage

``` r
at_roi_freehand(
  coords,
  label,
  level = 0L,
  simplify = 0,
  ...,
  call = rlang::caller_env()
)
```

## Arguments

- coords:

  Two-column numeric matrix of vertices in drawing order.

- label:

  Single string class label.

- level:

  Integer pyramid level the coordinates refer to. Default `0`.

- simplify:

  Non-negative Douglas-Peucker tolerance (`dTolerance`) applied to the
  closed polygon. `0` (default) keeps every vertex.

- ...:

  Additional named attributes stored on the ROI. The reserved names
  `author`, `source`, and `id` set those fields; all others become user
  attributes.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with `POLYGON` geometry.

## See also

Other rois:
[`at_roi_area()`](https://cttir.github.io/annotatR/reference/at_roi_area.md),
[`at_roi_bbox()`](https://cttir.github.io/annotatR/reference/at_roi_bbox.md),
[`at_roi_centroid()`](https://cttir.github.io/annotatR/reference/at_roi_centroid.md),
[`at_roi_circle()`](https://cttir.github.io/annotatR/reference/at_roi_circle.md),
[`at_roi_ellipse()`](https://cttir.github.io/annotatR/reference/at_roi_ellipse.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_roi_from_sf()`](https://cttir.github.io/annotatR/reference/at_roi_from_sf.md),
[`at_roi_point()`](https://cttir.github.io/annotatR/reference/at_roi_point.md),
[`at_roi_polygon()`](https://cttir.github.io/annotatR/reference/at_roi_polygon.md),
[`at_roi_rect()`](https://cttir.github.io/annotatR/reference/at_roi_rect.md)

## Examples

``` r
pts <- cbind(c(0, 5, 10, 5), c(0, 2, 0, -2))
r <- at_roi_freehand(pts, label = "trace")
```
