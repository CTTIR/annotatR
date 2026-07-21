# Create a rectangular ROI

Create a rectangular ROI

## Usage

``` r
at_roi_rect(
  xmin,
  ymin,
  xmax,
  ymax,
  label,
  level = 0L,
  ...,
  call = rlang::caller_env()
)
```

## Arguments

- xmin, ymin, xmax, ymax:

  Numeric bounds in image pixels. `xmax`/`ymax` must exceed
  `xmin`/`ymin`.

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
with `POLYGON` geometry (an axis-aligned rectangle).

## See also

Other rois:
[`at_roi_area()`](https://cttir.github.io/annotatR/reference/at_roi_area.md),
[`at_roi_bbox()`](https://cttir.github.io/annotatR/reference/at_roi_bbox.md),
[`at_roi_centroid()`](https://cttir.github.io/annotatR/reference/at_roi_centroid.md),
[`at_roi_circle()`](https://cttir.github.io/annotatR/reference/at_roi_circle.md),
[`at_roi_ellipse()`](https://cttir.github.io/annotatR/reference/at_roi_ellipse.md),
[`at_roi_freehand()`](https://cttir.github.io/annotatR/reference/at_roi_freehand.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_roi_from_sf()`](https://cttir.github.io/annotatR/reference/at_roi_from_sf.md),
[`at_roi_point()`](https://cttir.github.io/annotatR/reference/at_roi_point.md),
[`at_roi_polygon()`](https://cttir.github.io/annotatR/reference/at_roi_polygon.md)

## Examples

``` r
r <- at_roi_rect(0, 0, 10, 5, label = "tissue")
at_roi_bbox(r)
#> [1]  0  0 10  5
```
