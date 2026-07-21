# Check geometry across a whole session

Run
[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md)
on every materialised project in the session and stack the reports. Like
[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md)
(and unlike the assertion
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)),
this returns a report rather than throwing.

## Usage

``` r
at_batch_check_geometry(session, call = rlang::caller_env())
```

## Arguments

- session:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `image`, `roi_id`, `issue`, and `severity`. A 0-row tibble
when all geometry is valid.

## See also

[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md)

Other batch:
[`at_batch_apply()`](https://cttir.github.io/annotatR/reference/at_batch_apply.md),
[`at_export_all()`](https://cttir.github.io/annotatR/reference/at_export_all.md),
[`at_summary_table()`](https://cttir.github.io/annotatR/reference/at_summary_table.md)
