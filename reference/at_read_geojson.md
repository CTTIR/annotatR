# Read ROIs from a GeoJSON file

Read ROIs from a GeoJSON file

## Usage

``` r
at_read_geojson(
  path,
  layer_name = NULL,
  level = 0L,
  flip_y = FALSE,
  height = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- path:

  Path to a GeoJSON file.

- layer_name:

  Layer name for the imported ROIs; taken from the features' `layer`
  property when `NULL`.

- level:

  Integer level to record when a feature has no `level` property.

- flip_y:

  Logical; invert the y-axis on read. Default `FALSE`.

- height:

  Image height in pixels, required when `flip_y = TRUE`.

- call:

  The calling environment, for error reporting.

## Value

A named list of
[annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
objects (one per distinct `layer` property), or a single
[annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
when `layer_name` is supplied.

## See also

Other io:
[`at_load_project()`](https://cttir.github.io/annotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/annotatR/reference/at_load_session.md),
[`at_read_qupath()`](https://cttir.github.io/annotatR/reference/at_read_qupath.md),
[`at_read_rois_csv()`](https://cttir.github.io/annotatR/reference/at_read_rois_csv.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/annotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/annotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/annotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/annotatR/reference/at_write_rois_csv.md)
