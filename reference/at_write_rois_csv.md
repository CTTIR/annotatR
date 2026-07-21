# Write a project's ROIs to CSV

One row per ROI with a WKT `geometry` column.

## Usage

``` r
at_write_rois_csv(project, path, overwrite = FALSE, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- path:

  Output `.csv` path.

- overwrite:

  Logical; overwrite an existing file. Default `FALSE`.

- call:

  The calling environment, for error reporting.

## Value

The path, invisibly.

## See also

[`at_read_rois_csv()`](https://cttir.github.io/annotatR/reference/at_read_rois_csv.md)

Other io:
[`at_load_project()`](https://cttir.github.io/annotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/annotatR/reference/at_load_session.md),
[`at_read_geojson()`](https://cttir.github.io/annotatR/reference/at_read_geojson.md),
[`at_read_qupath()`](https://cttir.github.io/annotatR/reference/at_read_qupath.md),
[`at_read_rois_csv()`](https://cttir.github.io/annotatR/reference/at_read_rois_csv.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/annotatR/reference/at_save_project.md),
[`at_save_session()`](https://cttir.github.io/annotatR/reference/at_save_session.md),
[`at_write_geojson()`](https://cttir.github.io/annotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md)

## Examples

``` r
p <- withr::local_tempfile(fileext = ".csv")
at_write_rois_csv(at_example_project(), p)
```
