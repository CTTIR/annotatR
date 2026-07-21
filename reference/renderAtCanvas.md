# Render an annotation canvas in Shiny

Render an annotation canvas in Shiny

## Usage

``` r
renderAtCanvas(expr, env = parent.frame(), quoted = FALSE)
```

## Arguments

- expr:

  An expression producing an
  [`at_canvas()`](https://cttir.github.io/annotatR/reference/at_canvas.md).

- env:

  The environment to evaluate `expr` in.

- quoted:

  Is `expr` already quoted?

## Value

A Shiny render function.

## See also

Other shiny:
[`atCanvasOutput()`](https://cttir.github.io/annotatR/reference/atCanvasOutput.md),
[`at_annotate()`](https://cttir.github.io/annotatR/reference/at_annotate.md),
[`at_canvas()`](https://cttir.github.io/annotatR/reference/at_canvas.md),
[`at_canvas_fit()`](https://cttir.github.io/annotatR/reference/at_canvas_fit.md),
[`at_canvas_proxy()`](https://cttir.github.io/annotatR/reference/at_canvas_proxy.md),
[`at_canvas_set_annotations()`](https://cttir.github.io/annotatR/reference/at_canvas_set_annotations.md),
[`at_canvas_set_band()`](https://cttir.github.io/annotatR/reference/at_canvas_set_band.md),
[`at_canvas_set_overlay()`](https://cttir.github.io/annotatR/reference/at_canvas_set_overlay.md),
[`at_canvas_set_tool()`](https://cttir.github.io/annotatR/reference/at_canvas_set_tool.md),
[`at_tile_source()`](https://cttir.github.io/annotatR/reference/at_tile_source.md)
