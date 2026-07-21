# Plot a mask

Plot a mask

## Usage

``` r
at_plot_mask(mask, legend = TRUE, call = rlang::caller_env())
```

## Arguments

- mask:

  An `annot_mask`.

- legend:

  Logical; show the fill legend. Default `TRUE`.

- call:

  The calling environment, for error reporting.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.

## See also

Other plots:
[`at_plot()`](https://cttir.github.io/annotatR/reference/at_plot.md),
[`at_plot_image()`](https://cttir.github.io/annotatR/reference/at_plot_image.md),
[`at_plot_overlay()`](https://cttir.github.io/annotatR/reference/at_plot_overlay.md),
[`at_plot_project()`](https://cttir.github.io/annotatR/reference/at_plot_project.md),
[`at_plot_spectrum()`](https://cttir.github.io/annotatR/reference/at_plot_spectrum.md),
[`at_plot_summary()`](https://cttir.github.io/annotatR/reference/at_plot_summary.md)

## Examples

``` r
at_plot_mask(at_mask(at_example_project(), "labelled"))
```
