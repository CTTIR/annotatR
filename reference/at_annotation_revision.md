# Annotation revision token

A content revision for annotations: the SHA-256 of the canonical record
of every layer (name, labels, colours, z-order, visibility, lock) and
ROI (id, layer, label, level, geometry WKB, source, lock, review status,
plane and attributes). It changes whenever annotation content changes
and is independent of timestamps, authors, file paths and pixel data.
Partners pass it back as `expected_revision` to detect stale patches.

## Usage

``` r
at_annotation_revision(x, call = rlang::caller_env())
```

## Arguments

- x:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  [annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  or
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
  (combining every materialised project and the queue statuses).

- call:

  The calling environment, for error reporting.

## Value

A single string `"sha256:<64 hex>"`.

## See also

Other interop:
[`at_commit_qupflowr()`](https://cttir.github.io/annotatR/reference/at_commit_qupflowr.md),
[`at_export_qupflowr()`](https://cttir.github.io/annotatR/reference/at_export_qupflowr.md),
[`at_import_qupflowr()`](https://cttir.github.io/annotatR/reference/at_import_qupflowr.md),
[`at_interop_capabilities()`](https://cttir.github.io/annotatR/reference/at_interop_capabilities.md),
[`at_interop_manifest()`](https://cttir.github.io/annotatR/reference/at_interop_manifest.md),
[`at_stage_qupflowr()`](https://cttir.github.io/annotatR/reference/at_stage_qupflowr.md)

## Examples

``` r
proj <- at_example_project()
at_annotation_revision(proj)
#> [1] "sha256:6b91babfc88f9fa8593075b60d31a11fb82d3fdb8c368c99e0fe76cffc065321"
```
