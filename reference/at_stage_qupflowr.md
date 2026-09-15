# Stage partner changes against an annotatR project

Compute, without applying, the changes a partner patch would make to an
annotatR project: ROIs are joined by id and classified as `create`,
`update`, `unchanged`, `delete` (only with `delete_missing = TRUE`) or
`conflict`. Reviewed or locked ROIs, and ROIs in locked layers, are
never changed automatically; such changes become conflicts. When
`expected_revision` is given and the project has moved on, staging
aborts with an `at_conflict_error` (`REVISION_CONFLICT`).

## Usage

``` r
at_stage_qupflowr(
  x,
  patch,
  expected_revision = NULL,
  delete_missing = FALSE,
  call = rlang::caller_env()
)
```

## Arguments

- x:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  or the path of a saved project `.rds` (then the commit re-reads and
  re-checks that file).

- patch:

  An import report from
  [`at_import_qupflowr()`](https://cttir.github.io/annotatR/reference/at_import_qupflowr.md),
  a handoff directory, or one or more
  [annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
  objects.

- expected_revision:

  Optional revision of `x` the partner based its patch on (see
  [`at_annotation_revision()`](https://cttir.github.io/annotatR/reference/at_annotation_revision.md)).

- delete_missing:

  Logical; treat ROIs absent from the patch's layers as deletions.
  Default `FALSE`.

- call:

  The calling environment, for error reporting.

## Value

An `at_staged_patch`: a list with `patch_id`, `state = "staged"`,
`created`, `base_revision`, `proposed_revision`, `operations` (tibble of
`op`, `roi_id`, `layer`, `label`, `reason`), `summary` (counts by `op`),
`base`, `proposed` (the would-be project), `target_path` and
`patch_digest`.

## See also

[`at_commit_qupflowr()`](https://cttir.github.io/annotatR/reference/at_commit_qupflowr.md)

Other interop:
[`at_annotation_revision()`](https://cttir.github.io/annotatR/reference/at_annotation_revision.md),
[`at_commit_qupflowr()`](https://cttir.github.io/annotatR/reference/at_commit_qupflowr.md),
[`at_export_qupflowr()`](https://cttir.github.io/annotatR/reference/at_export_qupflowr.md),
[`at_import_qupflowr()`](https://cttir.github.io/annotatR/reference/at_import_qupflowr.md),
[`at_interop_capabilities()`](https://cttir.github.io/annotatR/reference/at_interop_capabilities.md),
[`at_interop_manifest()`](https://cttir.github.io/annotatR/reference/at_interop_manifest.md)

## Examples

``` r
proj <- at_example_project()
partner <- at_layer_add(at_layer("regions"), at_roi_rect(10, 10, 40, 40, label = "tumour",
                                                         id = "partner-1"))
st <- at_stage_qupflowr(proj, partner, expected_revision = at_annotation_revision(proj))
st$summary
#> $create
#> [1] 1
#> 
#> $update
#> [1] 0
#> 
#> $unchanged
#> [1] 0
#> 
#> $delete
#> [1] 0
#> 
#> $conflict
#> [1] 0
#> 
```
