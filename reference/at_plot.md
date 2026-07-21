# Plot generic for annotatR objects

Plot generic for annotatR objects

## Usage

``` r
at_plot(x, ...)
```

## Arguments

- x:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  or `annot_mask`.

- ...:

  Passed to the specific plot function.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.

## See also

Other plots:
[`at_plot_image()`](https://cttir.github.io/annotatR/reference/at_plot_image.md),
[`at_plot_mask()`](https://cttir.github.io/annotatR/reference/at_plot_mask.md),
[`at_plot_overlay()`](https://cttir.github.io/annotatR/reference/at_plot_overlay.md),
[`at_plot_project()`](https://cttir.github.io/annotatR/reference/at_plot_project.md),
[`at_plot_spectrum()`](https://cttir.github.io/annotatR/reference/at_plot_spectrum.md),
[`at_plot_summary()`](https://cttir.github.io/annotatR/reference/at_plot_summary.md)

## Examples

``` r
at_plot(at_example_project())
```
