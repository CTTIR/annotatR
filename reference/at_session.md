# Create a batch annotation session

Create a batch annotation session

## Usage

``` r
at_session(
  paths,
  labels = character(),
  layers = NULL,
  out_dir = tempdir(),
  autosave = TRUE,
  ...,
  call = rlang::caller_env()
)
```

## Arguments

- paths:

  Character vector of image file paths forming the queue.

- labels:

  Character vector of the global label vocabulary.

- layers:

  An
  [annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  a list of them, or `NULL`. Applied as a template to every image
  visited.

- out_dir:

  Directory for autosave and exports. Defaults to a session temporary
  directory.

- autosave:

  Logical; whether to autosave on annotation commits. Default `TRUE`.

- ...:

  Additional named session metadata.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with a manifest over `paths`, all statuses `"pending"`, the cursor at
the first image, and projects not yet materialised.

## See also

[`at_next()`](https://cttir.github.io/annotatR/reference/at_next.md),
[`at_current()`](https://cttir.github.io/annotatR/reference/at_current.md),
[`at_resume()`](https://cttir.github.io/annotatR/reference/at_resume.md)

Other sessions:
[`at_current()`](https://cttir.github.io/annotatR/reference/at_current.md),
[`at_example_session()`](https://cttir.github.io/annotatR/reference/at_example_session.md),
[`at_goto()`](https://cttir.github.io/annotatR/reference/at_goto.md),
[`at_manifest()`](https://cttir.github.io/annotatR/reference/at_manifest.md),
[`at_next()`](https://cttir.github.io/annotatR/reference/at_next.md),
[`at_prev()`](https://cttir.github.io/annotatR/reference/at_prev.md),
[`at_resume()`](https://cttir.github.io/annotatR/reference/at_resume.md),
[`at_session_status()`](https://cttir.github.io/annotatR/reference/at_session_status.md),
[`at_set_status()`](https://cttir.github.io/annotatR/reference/at_set_status.md)

## Examples

``` r
# Build a session over the bundled example image copied several times:
# sess <- at_example_session(3)
```
