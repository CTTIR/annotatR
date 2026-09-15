# Import a qupflowR handoff or neutral interchange file

Read only the neutral contract, validate it, and return a namespaced
annotatR result together with a conversion report. For a handoff
directory the SHA-256 inventory (missing, extra, duplicate, resized,
altered or symlinked files), the manifest schema and major version, ROI
id uniqueness and the id join between manifest and GeoJSON, layers,
planes, mask dimensions, integer values and legend completeness are all
checked; any integrity or schema failure aborts with an
`at_validation_error`. Nothing is written, no analysis is started, and
foreign objects are never returned as if they were annotatR objects:
imported ROIs carry `source = "imported"` and partner fields under
`attributes$qupflowr`. An RDS file is refused, because deserialising it
is not a neutral read.

## Usage

``` r
at_import_qupflowr(
  file,
  format = c("auto", "handoff", "qupath_geojson", "geojson", "mask", "npy"),
  expected_revision = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- file:

  A handoff directory (or its `manifest.json`/`integrity.json`), a
  QuPath GeoJSON, a GeoJSON, a mask TIFF/PNG with legend sidecar, or a
  `.npy` mask.

- format:

  `"auto"` (default), `"handoff"`, `"qupath_geojson"`, `"geojson"`,
  `"mask"` or `"npy"`.

- expected_revision:

  Optional `"sha256:..."` annotation revision the caller expects the
  handoff to carry; a different revision aborts with an
  `at_conflict_error` (`REVISION_CONFLICT`).

- call:

  The calling environment, for error reporting.

## Value

An `at_import_report`: a list with `status`, `format`, `source_name`,
`handoff_digest`, `manifest`, `checks` (tibble of `check`, `status`,
`detail`), `objects` (`layers`: named list of
[annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md);
`masks`: named list of `annot_mask`; `images`: image records),
`conversion` (tibble with one row per ROI: `roi_id`, `layer`, `label`,
`source_object_id`, `object_type`, `geometry_fidelity`,
`geometry_match`, `notes`) and `annotation_revision` of the imported
layers.

## See also

[`at_export_qupflowr()`](https://cttir.github.io/annotatR/reference/at_export_qupflowr.md),
[`at_stage_qupflowr()`](https://cttir.github.io/annotatR/reference/at_stage_qupflowr.md)

Other interop:
[`at_annotation_revision()`](https://cttir.github.io/annotatR/reference/at_annotation_revision.md),
[`at_commit_qupflowr()`](https://cttir.github.io/annotatR/reference/at_commit_qupflowr.md),
[`at_export_qupflowr()`](https://cttir.github.io/annotatR/reference/at_export_qupflowr.md),
[`at_interop_capabilities()`](https://cttir.github.io/annotatR/reference/at_interop_capabilities.md),
[`at_interop_manifest()`](https://cttir.github.io/annotatR/reference/at_interop_manifest.md),
[`at_stage_qupflowr()`](https://cttir.github.io/annotatR/reference/at_stage_qupflowr.md)

## Examples

``` r
dest <- file.path(tempdir(), "handoff-import-example")
at_export_qupflowr(at_example_project(), dest, overwrite = TRUE)
rep <- at_import_qupflowr(dest)
rep$checks
#> # A tibble: 4 × 3
#>   check               status detail                                            
#>   <chr>               <chr>  <chr>                                             
#> 1 integrity           ok     5 files verified                                  
#> 2 manifest_schema     ok     1.0                                               
#> 3 annotations:project ok     3 ROIs joined by id                               
#> 4 masks               ok     1 masks: dimensions, integers and legends verified
```
