# Write a project's ROIs to GeoJSON

Write a project's ROIs to GeoJSON

## Usage

``` r
at_write_geojson(
  project,
  path,
  layer = NULL,
  level = 0L,
  flip_y = FALSE,
  overwrite = FALSE,
  call = rlang::caller_env()
)
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- path:

  Output file path.

- layer:

  Optional layer filter.

- level:

  Integer pyramid level for the coordinates. Default `0`.

- flip_y:

  Logical; invert the y-axis (for GIS-oriented consumers). Default
  `FALSE` (image orientation preserved). The consequence is documented
  in the interop vignette.

- overwrite:

  Logical; overwrite an existing file. Default `FALSE`.

- call:

  The calling environment, for error reporting.

## Value

The output path, invisibly.

## See also

[`at_read_geojson()`](https://cttir.github.io/annotatR/reference/at_read_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md)

Other io:
[`at_load_project()`](https://cttir.github.io/annotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/annotatR/reference/at_load_session.md),
[`at_read_geojson()`](https://cttir.github.io/annotatR/reference/at_read_geojson.md),
[`at_read_qupath()`](https://cttir.github.io/annotatR/reference/at_read_qupath.md),
[`at_read_rois_csv()`](https://cttir.github.io/annotatR/reference/at_read_rois_csv.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/annotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/annotatR/reference/at_save_session.md),
[`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/annotatR/reference/at_write_rois_csv.md)

## Examples

``` r
p <- withr::local_tempfile(fileext = ".geojson")
at_write_geojson(at_example_project(), p)
```
