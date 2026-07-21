# The session manifest

The session manifest

## Usage

``` r
at_session_status(session, call = rlang::caller_env())
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

The manifest
[tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `idx`, `path`, `name`, `status`, `project_path`, `n_rois`,
and `modified`.

## See also

Other sessions:
[`at_current()`](https://cttir.github.io/annotatR/reference/at_current.md),
[`at_example_session()`](https://cttir.github.io/annotatR/reference/at_example_session.md),
[`at_goto()`](https://cttir.github.io/annotatR/reference/at_goto.md),
[`at_manifest()`](https://cttir.github.io/annotatR/reference/at_manifest.md),
[`at_next()`](https://cttir.github.io/annotatR/reference/at_next.md),
[`at_prev()`](https://cttir.github.io/annotatR/reference/at_prev.md),
[`at_resume()`](https://cttir.github.io/annotatR/reference/at_resume.md),
[`at_session()`](https://cttir.github.io/annotatR/reference/at_session.md),
[`at_set_status()`](https://cttir.github.io/annotatR/reference/at_set_status.md)
