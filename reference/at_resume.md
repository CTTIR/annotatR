# Resume a saved session

A more discoverable alias for
[`at_load_session()`](https://cttir.github.io/annotatR/reference/at_load_session.md).

## Usage

``` r
at_resume(path, call = rlang::caller_env())
```

## Arguments

- path:

  Path to a saved session `.rds` file.

- call:

  The calling environment, for error reporting.

## Value

The restored
[annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

## See also

[`at_save_session()`](https://cttir.github.io/annotatR/reference/at_save_session.md),
[`at_load_session()`](https://cttir.github.io/annotatR/reference/at_load_session.md)

Other sessions:
[`at_current()`](https://cttir.github.io/annotatR/reference/at_current.md),
[`at_example_session()`](https://cttir.github.io/annotatR/reference/at_example_session.md),
[`at_goto()`](https://cttir.github.io/annotatR/reference/at_goto.md),
[`at_manifest()`](https://cttir.github.io/annotatR/reference/at_manifest.md),
[`at_next()`](https://cttir.github.io/annotatR/reference/at_next.md),
[`at_prev()`](https://cttir.github.io/annotatR/reference/at_prev.md),
[`at_session()`](https://cttir.github.io/annotatR/reference/at_session.md),
[`at_session_status()`](https://cttir.github.io/annotatR/reference/at_session_status.md),
[`at_set_status()`](https://cttir.github.io/annotatR/reference/at_set_status.md)
