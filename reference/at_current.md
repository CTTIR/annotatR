# The current project

Return the project for the image at the cursor, materialising it from
the image (and applying the session's layer template) if it has not been
visited.

## Usage

``` r
at_current(session, call = rlang::caller_env())
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

An
[annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

## See also

Other sessions:
[`at_example_session()`](https://cttir.github.io/annotatR/reference/at_example_session.md),
[`at_goto()`](https://cttir.github.io/annotatR/reference/at_goto.md),
[`at_manifest()`](https://cttir.github.io/annotatR/reference/at_manifest.md),
[`at_next()`](https://cttir.github.io/annotatR/reference/at_next.md),
[`at_prev()`](https://cttir.github.io/annotatR/reference/at_prev.md),
[`at_resume()`](https://cttir.github.io/annotatR/reference/at_resume.md),
[`at_session()`](https://cttir.github.io/annotatR/reference/at_session.md),
[`at_session_status()`](https://cttir.github.io/annotatR/reference/at_session_status.md),
[`at_set_status()`](https://cttir.github.io/annotatR/reference/at_set_status.md)
