# Read ROIs from a QuPath GeoJSON file

Maps `classification.name` to the ROI label, `colorRGB` to the layer
style colour, and `object_type` to the ROI source. Features with a
`null` classification are imported as `"unclassified"`.

## Usage

``` r
at_read_qupath(
  path,
  layer_name = "qupath",
  level = 0L,
  call = rlang::caller_env()
)
```

## Arguments

- path:

  Path to a QuPath GeoJSON file.

- layer_name:

  Layer name for the imported ROIs. Default `"qupath"`.

- level:

  Integer level to record on the ROIs. Default `0`.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

## See also

Other io:
[`at_load_project()`](https://cttir.github.io/annotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/annotatR/reference/at_load_session.md),
[`at_read_geojson()`](https://cttir.github.io/annotatR/reference/at_read_geojson.md),
[`at_read_rois_csv()`](https://cttir.github.io/annotatR/reference/at_read_rois_csv.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/annotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/annotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/annotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/annotatR/reference/at_write_rois_csv.md)
