# Create an ROI from an existing sf geometry

Create an ROI from an existing sf geometry

## Usage

``` r
at_roi_from_sf(geometry, label, level = 0L, ..., call = rlang::caller_env())
```

## Arguments

- geometry:

  An `sf`, `sfc`, or `sfg` geometry in image pixel coordinates.

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
wrapping the supplied geometry.

## See also

Other rois:
[`at_roi_area()`](https://cttir.github.io/annotatR/reference/at_roi_area.md),
[`at_roi_bbox()`](https://cttir.github.io/annotatR/reference/at_roi_bbox.md),
[`at_roi_centroid()`](https://cttir.github.io/annotatR/reference/at_roi_centroid.md),
[`at_roi_circle()`](https://cttir.github.io/annotatR/reference/at_roi_circle.md),
[`at_roi_ellipse()`](https://cttir.github.io/annotatR/reference/at_roi_ellipse.md),
[`at_roi_freehand()`](https://cttir.github.io/annotatR/reference/at_roi_freehand.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_roi_point()`](https://cttir.github.io/annotatR/reference/at_roi_point.md),
[`at_roi_polygon()`](https://cttir.github.io/annotatR/reference/at_roi_polygon.md),
[`at_roi_rect()`](https://cttir.github.io/annotatR/reference/at_roi_rect.md)

## Examples

``` r
g <- sf::st_point(c(3, 4))
r <- at_roi_from_sf(g, label = "imported", source = "imported")
```
