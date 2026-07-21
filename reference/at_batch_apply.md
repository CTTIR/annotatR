# Apply a function to every project in a session

Apply a function to every project in a session

## Usage

``` r
at_batch_apply(
  session,
  fn,
  ...,
  scope = "all",
  progress = TRUE,
  call = rlang::caller_env()
)
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- fn:

  A function `fn(project, image, idx)` returning an
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- ...:

  Passed to `fn`.

- scope:

  `"all"` (default), `"complete"`, `"current"`, or `"flagged"`.

- progress:

  Logical; show a progress bar. Default `TRUE`.

- call:

  The calling environment, for error reporting.

## Value

The
[annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with modified projects.

## See also

Other batch:
[`at_batch_check_geometry()`](https://cttir.github.io/annotatR/reference/at_batch_check_geometry.md),
[`at_export_all()`](https://cttir.github.io/annotatR/reference/at_export_all.md),
[`at_summary_table()`](https://cttir.github.io/annotatR/reference/at_summary_table.md)
