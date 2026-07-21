# Plot a project's ROIs

Plot a project's ROIs

## Usage

``` r
at_plot_project(
  project,
  layer = NULL,
  label = NULL,
  show_labels = TRUE,
  alpha = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- layer, label:

  Optional filters.

- show_labels:

  Logical; draw label text at centroids. Default `TRUE`.

- alpha:

  Fill opacity; a sensible default when `NULL`.

- call:

  The calling environment, for error reporting.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object. Empty projects give a valid empty plot.

## See also

Other plots:
[`at_plot()`](https://cttir.github.io/annotatR/reference/at_plot.md),
[`at_plot_image()`](https://cttir.github.io/annotatR/reference/at_plot_image.md),
[`at_plot_mask()`](https://cttir.github.io/annotatR/reference/at_plot_mask.md),
[`at_plot_overlay()`](https://cttir.github.io/annotatR/reference/at_plot_overlay.md),
[`at_plot_spectrum()`](https://cttir.github.io/annotatR/reference/at_plot_spectrum.md),
[`at_plot_summary()`](https://cttir.github.io/annotatR/reference/at_plot_summary.md)

## Examples

``` r
at_plot_project(at_example_project())
```
