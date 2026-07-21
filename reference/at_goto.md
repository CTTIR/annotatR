# Jump to a specific image

Jump to a specific image

## Usage

``` r
at_goto(session, i, call = rlang::caller_env())
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- i:

  Integer image index (1-based) within the queue.

- call:

  The calling environment, for error reporting.

## Value

A new
[annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with the cursor at `i`.

## See also

Other sessions:
[`at_current()`](https://cttir.github.io/annotatR/reference/at_current.md),
[`at_example_session()`](https://cttir.github.io/annotatR/reference/at_example_session.md),
[`at_manifest()`](https://cttir.github.io/annotatR/reference/at_manifest.md),
[`at_next()`](https://cttir.github.io/annotatR/reference/at_next.md),
[`at_prev()`](https://cttir.github.io/annotatR/reference/at_prev.md),
[`at_resume()`](https://cttir.github.io/annotatR/reference/at_resume.md),
[`at_session()`](https://cttir.github.io/annotatR/reference/at_session.md),
[`at_session_status()`](https://cttir.github.io/annotatR/reference/at_session_status.md),
[`at_set_status()`](https://cttir.github.io/annotatR/reference/at_set_status.md)
