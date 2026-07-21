# Plot spectra

Plot spectra

## Usage

``` r
at_plot_spectrum(
  spectra,
  colour_by = c("label", "roi_id", "layer"),
  ribbon = TRUE,
  call = rlang::caller_env()
)
```

## Arguments

- spectra:

  The long tibble from
  [`at_extract_spectrum()`](https://cttir.github.io/annotatR/reference/at_extract_spectrum.md)
  or
  [`at_extract()`](https://cttir.github.io/annotatR/reference/at_extract.md).

- colour_by:

  One of `"label"`, `"roi_id"`, or `"layer"`.

- ribbon:

  Logical; draw a min-max ribbon per colour group.

- call:

  The calling environment, for error reporting.

## Value

A [ggplot2::ggplot](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.

## See also

Other plots:
[`at_plot()`](https://cttir.github.io/annotatR/reference/at_plot.md),
[`at_plot_image()`](https://cttir.github.io/annotatR/reference/at_plot_image.md),
[`at_plot_mask()`](https://cttir.github.io/annotatR/reference/at_plot_mask.md),
[`at_plot_overlay()`](https://cttir.github.io/annotatR/reference/at_plot_overlay.md),
[`at_plot_project()`](https://cttir.github.io/annotatR/reference/at_plot_project.md),
[`at_plot_summary()`](https://cttir.github.io/annotatR/reference/at_plot_summary.md)
