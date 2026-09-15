# Commit a staged partner patch

Apply an
[`at_stage_qupflowr()`](https://cttir.github.io/annotatR/reference/at_stage_qupflowr.md)
patch. Conflicting operations are never applied. The commit is
idempotent: repeating it with the same `idempotency_key` and the same
patch returns the original receipt without applying anything again,
while the same key with a different patch aborts with
`IDEMPOTENCY_CONFLICT`. When the patch targets a saved project file (or
`destination` names one), the file is re-read and its revision
re-checked immediately before writing; an existing file is only replaced
with `overwrite = TRUE`. A `<file>.commit.json` receipt records the key
across R sessions.

## Usage

``` r
at_commit_qupflowr(
  x,
  idempotency_key = NULL,
  destination = NULL,
  overwrite = FALSE,
  call = rlang::caller_env()
)
```

## Arguments

- x:

  An `at_staged_patch`.

- idempotency_key:

  Optional client key; defaults to one derived from the patch id.

- destination:

  Optional project `.rds` path to write the committed project to;
  defaults to the patch's `target_path` when staged from a file.

- overwrite:

  Logical; allow replacing an existing project file.

- call:

  The calling environment, for error reporting.

## Value

An `at_commit_receipt`: a list with `state = "committed"`, `patch_id`,
`idempotency_key`, `previous_revision`, `new_revision`, `applied` and
`conflicts` (operation tibbles), `project`, `written` (path or `NA`),
`committed_at` and `replayed`.

## See also

[`at_stage_qupflowr()`](https://cttir.github.io/annotatR/reference/at_stage_qupflowr.md)

Other interop:
[`at_annotation_revision()`](https://cttir.github.io/annotatR/reference/at_annotation_revision.md),
[`at_export_qupflowr()`](https://cttir.github.io/annotatR/reference/at_export_qupflowr.md),
[`at_import_qupflowr()`](https://cttir.github.io/annotatR/reference/at_import_qupflowr.md),
[`at_interop_capabilities()`](https://cttir.github.io/annotatR/reference/at_interop_capabilities.md),
[`at_interop_manifest()`](https://cttir.github.io/annotatR/reference/at_interop_manifest.md),
[`at_stage_qupflowr()`](https://cttir.github.io/annotatR/reference/at_stage_qupflowr.md)

## Examples

``` r
proj <- at_example_project()
partner <- at_layer_add(at_layer("regions"), at_roi_rect(10, 10, 40, 40, label = "tumour",
                                                         id = "partner-1"))
rc <- at_commit_qupflowr(at_stage_qupflowr(proj, partner))
rc$new_revision
#> [1] "sha256:396c6f1b1c47c173d8b72b769cfb3ae37576c3fdad492f8ec656b05b6ca3a525"
```
