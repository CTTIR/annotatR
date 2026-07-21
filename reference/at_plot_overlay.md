# Plot ROIs overlaid on the image

Plot ROIs overlaid on the image

## Usage

``` r
at_plot_overlay(project, img = NULL, layer = NULL, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- img:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md);
  the project's image by default.

- layer:

  Optional layer filter.

- call:

  The calling environment, for error reporting.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object with the image and ROI outlines.

## See also

Other plots:
[`at_plot()`](https://cttir.github.io/annotatR/reference/at_plot.md),
[`at_plot_image()`](https://cttir.github.io/annotatR/reference/at_plot_image.md),
[`at_plot_mask()`](https://cttir.github.io/annotatR/reference/at_plot_mask.md),
[`at_plot_project()`](https://cttir.github.io/annotatR/reference/at_plot_project.md),
[`at_plot_spectrum()`](https://cttir.github.io/annotatR/reference/at_plot_spectrum.md),
[`at_plot_summary()`](https://cttir.github.io/annotatR/reference/at_plot_summary.md)

## Examples

``` r
at_plot_overlay(at_example_project())
```
