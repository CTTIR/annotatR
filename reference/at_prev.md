# Step back to the previous image

Step back to the previous image

## Usage

``` r
at_prev(session, call = rlang::caller_env())
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A new
[annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with the cursor decremented (clamped at 1).

## See also

Other sessions:
[`at_current()`](https://cttir.github.io/annotatR/reference/at_current.md),
[`at_example_session()`](https://cttir.github.io/annotatR/reference/at_example_session.md),
[`at_goto()`](https://cttir.github.io/annotatR/reference/at_goto.md),
[`at_manifest()`](https://cttir.github.io/annotatR/reference/at_manifest.md),
[`at_next()`](https://cttir.github.io/annotatR/reference/at_next.md),
[`at_resume()`](https://cttir.github.io/annotatR/reference/at_resume.md),
[`at_session()`](https://cttir.github.io/annotatR/reference/at_session.md),
[`at_session_status()`](https://cttir.github.io/annotatR/reference/at_session_status.md),
[`at_set_status()`](https://cttir.github.io/annotatR/reference/at_set_status.md)
