# Load a project

Load a project

## Usage

``` r
at_load_project(path, call = rlang::caller_env())
```

## Arguments

- path:

  Path to a saved project `.rds`.

- call:

  The calling environment, for error reporting.

## Value

The
[annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).
Warns if the file was written by a newer annotatR.

## See also

Other io:
[`at_load_session()`](https://cttir.github.io/annotatR/reference/at_load_session.md),
[`at_read_geojson()`](https://cttir.github.io/annotatR/reference/at_read_geojson.md),
[`at_read_qupath()`](https://cttir.github.io/annotatR/reference/at_read_qupath.md),
[`at_read_rois_csv()`](https://cttir.github.io/annotatR/reference/at_read_rois_csv.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/annotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/annotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/annotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/annotatR/reference/at_write_rois_csv.md)
