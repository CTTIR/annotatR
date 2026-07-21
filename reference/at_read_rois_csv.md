# Read ROIs from a CSV with WKT geometry

Read ROIs from a CSV with WKT geometry

## Usage

``` r
at_read_rois_csv(path, layer_name = "csv", call = rlang::caller_env())
```

## Arguments

- path:

  Path to a CSV with at least `label` and `geometry` (WKT) columns.
  Other columns (`level`, `author`, `source`, ...) are used when
  present.

- layer_name:

  Layer name for the imported ROIs. Default `"csv"`.

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
[`at_read_qupath()`](https://cttir.github.io/annotatR/reference/at_read_qupath.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/annotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/annotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/annotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/annotatR/reference/at_write_rois_csv.md)
