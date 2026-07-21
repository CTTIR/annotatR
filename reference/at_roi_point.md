# Create a point ROI

Create a point ROI

## Usage

``` r
at_roi_point(x, y, label, level = 0L, ..., call = rlang::caller_env())
```

## Arguments

- x, y:

  Numeric coordinates of the point, in image pixels.

- label:

  Single string class label.

- level:

  Integer pyramid level the coordinates refer to. Default `0`.

- ...:

  Additional named attributes stored on the ROI. The reserved names
  `author`, `source`, and `id` set those fields; all others become user
  attributes.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with `POINT` geometry.

## See also

[`at_roi_rect()`](https://cttir.github.io/annotatR/reference/at_roi_rect.md),
[`at_roi_polygon()`](https://cttir.github.io/annotatR/reference/at_roi_polygon.md)

Other rois:
[`at_roi_area()`](https://cttir.github.io/annotatR/reference/at_roi_area.md),
[`at_roi_bbox()`](https://cttir.github.io/annotatR/reference/at_roi_bbox.md),
[`at_roi_centroid()`](https://cttir.github.io/annotatR/reference/at_roi_centroid.md),
[`at_roi_circle()`](https://cttir.github.io/annotatR/reference/at_roi_circle.md),
[`at_roi_ellipse()`](https://cttir.github.io/annotatR/reference/at_roi_ellipse.md),
[`at_roi_freehand()`](https://cttir.github.io/annotatR/reference/at_roi_freehand.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_roi_from_sf()`](https://cttir.github.io/annotatR/reference/at_roi_from_sf.md),
[`at_roi_polygon()`](https://cttir.github.io/annotatR/reference/at_roi_polygon.md),
[`at_roi_rect()`](https://cttir.github.io/annotatR/reference/at_roi_rect.md)

## Examples

``` r
r <- at_roi_point(10, 20, label = "cell")
at_roi_centroid(r)
#> [1] 10 20
```
