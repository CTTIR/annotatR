# Read ROIs from a QuPath GeoJSON file

Reads QuPath 0.4+ exports (a FeatureCollection or a bare feature array)
and the legacy annotatR 0.1 dialect. `classification.name` (or the
joined `names` of a derived class, e.g. `"Tumor: Positive"`) becomes the
ROI label, the classification colour the layer style colour, and
features without a classification are labelled `"unclassified"`.
Everything else QuPath carries is kept, never invented, under each ROI's
`attributes$qupath`: the object id and type, name, measurements (with
explicit `value_state`), the image plane (zero-based `c`, `z`, `t`;
`c = NA` for all channels), metadata, a nucleus geometry, and
`roi_native = "ellipse"` with `geometry_fidelity = "approximated"` for
polygonised ellipses. An annotatR id stored in
`metadata.annotatr_roi_id` is restored as the ROI id.

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
