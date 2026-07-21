# Convert a GeoJSON feature to an ROI

Turn a single parsed GeoJSON feature (a list with `geometry` and
optional `properties`) into an
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).
Useful for consuming interactive drawing output.

## Usage

``` r
at_roi_from_geojson(
  feature,
  label = NULL,
  level = 0L,
  source = "manual",
  call = rlang::caller_env()
)
```

## Arguments

- feature:

  A parsed GeoJSON feature: a list with a `geometry` element (`type` and
  `coordinates`) and optional `properties`.

- label:

  Single string class label; taken from `properties$label` when `NULL`.

- level:

  Integer pyramid level. Default `0`.

- source:

  Provenance source string. Default `"manual"`.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

## See also

Other io:
[`at_load_project()`](https://cttir.github.io/annotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/annotatR/reference/at_load_session.md),
[`at_read_geojson()`](https://cttir.github.io/annotatR/reference/at_read_geojson.md),
[`at_read_qupath()`](https://cttir.github.io/annotatR/reference/at_read_qupath.md),
[`at_read_rois_csv()`](https://cttir.github.io/annotatR/reference/at_read_rois_csv.md),
[`at_save_project()`](https://cttir.github.io/annotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/annotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/annotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/annotatR/reference/at_write_rois_csv.md)

Other rois:
[`at_roi_area()`](https://cttir.github.io/annotatR/reference/at_roi_area.md),
[`at_roi_bbox()`](https://cttir.github.io/annotatR/reference/at_roi_bbox.md),
[`at_roi_centroid()`](https://cttir.github.io/annotatR/reference/at_roi_centroid.md),
[`at_roi_circle()`](https://cttir.github.io/annotatR/reference/at_roi_circle.md),
[`at_roi_ellipse()`](https://cttir.github.io/annotatR/reference/at_roi_ellipse.md),
[`at_roi_freehand()`](https://cttir.github.io/annotatR/reference/at_roi_freehand.md),
[`at_roi_from_sf()`](https://cttir.github.io/annotatR/reference/at_roi_from_sf.md),
[`at_roi_point()`](https://cttir.github.io/annotatR/reference/at_roi_point.md),
[`at_roi_polygon()`](https://cttir.github.io/annotatR/reference/at_roi_polygon.md),
[`at_roi_rect()`](https://cttir.github.io/annotatR/reference/at_roi_rect.md)

## Examples

``` r
feat <- list(geometry = list(type = "Polygon",
  coordinates = list(list(c(0, 0), c(4, 0), c(4, 4), c(0, 4), c(0, 0)))))
at_roi_from_geojson(feat, label = "region")
#> <annot_roi> region (POLYGON)
#> id: "roi_000000060"  |  level: 0  |  source: manual
#> bbox: [0, 0] - [4, 4]
```
