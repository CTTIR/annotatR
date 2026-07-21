# Save a session

Save a session

## Usage

``` r
at_save_session(
  session,
  path = NULL,
  overwrite = FALSE,
  call = rlang::caller_env()
)
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- path:

  Optional output path; defaults to `_session.rds` in `out_dir`.

- overwrite:

  Logical; overwrite an existing file. Default `FALSE`.

- call:

  The calling environment, for error reporting.

## Value

The session, invisibly.

## See also

[`at_load_session()`](https://cttir.github.io/annotatR/reference/at_load_session.md),
[`at_resume()`](https://cttir.github.io/annotatR/reference/at_resume.md)

Other io:
[`at_load_project()`](https://cttir.github.io/annotatR/reference/at_load_project.md),
[`at_load_session()`](https://cttir.github.io/annotatR/reference/at_load_session.md),
[`at_read_geojson()`](https://cttir.github.io/annotatR/reference/at_read_geojson.md),
[`at_read_qupath()`](https://cttir.github.io/annotatR/reference/at_read_qupath.md),
[`at_read_rois_csv()`](https://cttir.github.io/annotatR/reference/at_read_rois_csv.md),
[`at_roi_from_geojson()`](https://cttir.github.io/annotatR/reference/at_roi_from_geojson.md),
[`at_save_project()`](https://cttir.github.io/annotatR/reference/at_save_project.md),
[`at_write_geojson()`](https://cttir.github.io/annotatR/reference/at_write_geojson.md),
[`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md),
[`at_write_rois_csv()`](https://cttir.github.io/annotatR/reference/at_write_rois_csv.md)
