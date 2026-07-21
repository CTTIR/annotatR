# Set the displayed band or RGB triple

Set the displayed band or RGB triple

## Usage

``` r
at_canvas_set_band(proxy, band, call = rlang::caller_env())
```

## Arguments

- proxy:

  An `atcanvas_proxy`.

- band:

  A band index or a length-3 vector of band indices.

- call:

  The calling environment, for error reporting.

## Value

The proxy, invisibly.

## See also

Other shiny:
[`atCanvasOutput()`](https://cttir.github.io/annotatR/reference/atCanvasOutput.md),
[`at_annotate()`](https://cttir.github.io/annotatR/reference/at_annotate.md),
[`at_canvas()`](https://cttir.github.io/annotatR/reference/at_canvas.md),
[`at_canvas_fit()`](https://cttir.github.io/annotatR/reference/at_canvas_fit.md),
[`at_canvas_proxy()`](https://cttir.github.io/annotatR/reference/at_canvas_proxy.md),
[`at_canvas_set_annotations()`](https://cttir.github.io/annotatR/reference/at_canvas_set_annotations.md),
[`at_canvas_set_overlay()`](https://cttir.github.io/annotatR/reference/at_canvas_set_overlay.md),
[`at_canvas_set_tool()`](https://cttir.github.io/annotatR/reference/at_canvas_set_tool.md),
[`at_tile_source()`](https://cttir.github.io/annotatR/reference/at_tile_source.md),
[`renderAtCanvas()`](https://cttir.github.io/annotatR/reference/renderAtCanvas.md)
