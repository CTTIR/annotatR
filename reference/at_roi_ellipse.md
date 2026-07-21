# Create an elliptical ROI

Create an elliptical ROI

## Usage

``` r
at_roi_ellipse(
  x,
  y,
  rx,
  ry,
  rotation = 0,
  label,
  level = 0L,
  n_seg = 64L,
  ...,
  call = rlang::caller_env()
)
```

## Arguments

- x, y:

  Numeric centre coordinates in image pixels.

- rx, ry:

  Positive numeric semi-axis lengths in pixels.

- rotation:

  Rotation of the major axis in degrees, clockwise in image orientation.
  Default `0`.

- label:

  Single string class label.

- level:

  Integer pyramid level the coordinates refer to. Default `0`.

- n_seg:

  Integer number of polygon segments approximating the ellipse.

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
[`at_roi_freehand()`](https://cttir.github.io/annotatR/reference/at_roi_freehand.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_roi_from_sf()`](https://cttir.github.io/annotatR/reference/at_roi_from_sf.md),
[`at_roi_point()`](https://cttir.github.io/annotatR/reference/at_roi_point.md),
[`at_roi_polygon()`](https://cttir.github.io/annotatR/reference/at_roi_polygon.md),
[`at_roi_rect()`](https://cttir.github.io/annotatR/reference/at_roi_rect.md)

## Examples

``` r
r <- at_roi_ellipse(50, 50, rx = 20, ry = 10, rotation = 30, label = "cell")
```
