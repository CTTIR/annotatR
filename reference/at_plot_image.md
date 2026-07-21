# Plot an image

Plot an image

## Usage

``` r
at_plot_image(
  img,
  level = NULL,
  bands = NULL,
  rgb = NULL,
  max_dim = 1024L,
  call = rlang::caller_env()
)
```

## Arguments

- img:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- level:

  Pyramid level to display; chosen automatically when `NULL`.

- bands:

  Optional band index for single-band display.

- rgb:

  Optional length-3 vector of band indices, or wavelengths in nm for a
  spectral cube, for a false-colour composite.

- max_dim:

  Maximum display dimension (auto-downsampled). Default `1024`.

- call:

  The calling environment, for error reporting.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.

## See also

Other plots:
[`at_plot()`](https://cttir.github.io/annotatR/reference/at_plot.md),
[`at_plot_mask()`](https://cttir.github.io/annotatR/reference/at_plot_mask.md),
[`at_plot_overlay()`](https://cttir.github.io/annotatR/reference/at_plot_overlay.md),
[`at_plot_project()`](https://cttir.github.io/annotatR/reference/at_plot_project.md),
[`at_plot_spectrum()`](https://cttir.github.io/annotatR/reference/at_plot_spectrum.md),
[`at_plot_summary()`](https://cttir.github.io/annotatR/reference/at_plot_summary.md)

## Examples

``` r
at_plot_image(at_example_image("tissue"))
```
