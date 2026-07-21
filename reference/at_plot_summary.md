# Plot a project summary

Plot a project summary

## Usage

``` r
at_plot_summary(project, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object of per-label ROI area distributions.

## See also

Other plots:
[`at_plot()`](https://cttir.github.io/annotatR/reference/at_plot.md),
[`at_plot_image()`](https://cttir.github.io/annotatR/reference/at_plot_image.md),
[`at_plot_mask()`](https://cttir.github.io/annotatR/reference/at_plot_mask.md),
[`at_plot_overlay()`](https://cttir.github.io/annotatR/reference/at_plot_overlay.md),
[`at_plot_project()`](https://cttir.github.io/annotatR/reference/at_plot_project.md),
[`at_plot_spectrum()`](https://cttir.github.io/annotatR/reference/at_plot_spectrum.md)
