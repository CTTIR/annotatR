# Build a partner interop manifest

Describe annotatR objects for a partner such as qupflowR without
exposing local paths: images are identified by content hash (`image_id`)
and file basename; annotations by string ROI ids and an
[`at_annotation_revision()`](https://cttir.github.io/annotatR/reference/at_annotation_revision.md);
masks by type, integer dtype, background, dimensions, level and legend.
The coordinate convention, band/wavelength table, HSI value semantics,
plane, calibration and transform digests are recorded explicitly. QuPath
hierarchy and native ROI shapes, which annotatR does not model, are
reported as `"unknown"` or `"approximated"`, never invented.

## Usage

``` r
at_interop_manifest(
  x,
  destination = NULL,
  hash_sources = TRUE,
  call = rlang::caller_env()
)
```

## Arguments

- x:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  [annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
  or `annot_mask`.

- destination:

  Optional path: an existing directory (the manifest is written as
  `manifest.json` inside it) or a `.json` file path. An existing file is
  never overwritten.

- hash_sources:

  Logical; hash image source files (needed for a content-derived
  `image_id`). Default `TRUE`.

- call:

  The calling environment, for error reporting.

## Value

The manifest (a list of class `at_interop_manifest`); invisibly when
`destination` is given.

## See also

[`at_export_qupflowr()`](https://cttir.github.io/annotatR/reference/at_export_qupflowr.md),
[`at_interop_capabilities()`](https://cttir.github.io/annotatR/reference/at_interop_capabilities.md)

Other interop:
[`at_annotation_revision()`](https://cttir.github.io/annotatR/reference/at_annotation_revision.md),
[`at_commit_qupflowr()`](https://cttir.github.io/annotatR/reference/at_commit_qupflowr.md),
[`at_export_qupflowr()`](https://cttir.github.io/annotatR/reference/at_export_qupflowr.md),
[`at_import_qupflowr()`](https://cttir.github.io/annotatR/reference/at_import_qupflowr.md),
[`at_interop_capabilities()`](https://cttir.github.io/annotatR/reference/at_interop_capabilities.md),
[`at_stage_qupflowr()`](https://cttir.github.io/annotatR/reference/at_stage_qupflowr.md)

## Examples

``` r
m <- at_interop_manifest(at_example_project())
m$annotations$annotation_revision
#> [1] "sha256:10f56448a98dc069007b9366fb6c4eaf3777abea004593e3f5b7d0fb6fd2d052"
m$images[[1]]$image_id
#> [1] "sha256:3fa00078c93c3a7d"
```
