# Zoom the canvas to a bounding box

Zoom the canvas to a bounding box

## Usage

``` r
at_canvas_fit(proxy, bbox = NULL, call = rlang::caller_env())
```

## Arguments

- proxy:

  An `atcanvas_proxy`.

- bbox:

  Optional `c(xmin, ymin, xmax, ymax)` in level-0 pixels; fits the whole
  image when `NULL`.

- call:

  The calling environment, for error reporting.

## Value

The proxy, invisibly.

## See also

Other shiny:
[`atCanvasOutput()`](https://cttir.github.io/annotatR/reference/atCanvasOutput.md),
[`at_annotate()`](https://cttir.github.io/annotatR/reference/at_annotate.md),
[`at_canvas()`](https://cttir.github.io/annotatR/reference/at_canvas.md),
[`at_canvas_proxy()`](https://cttir.github.io/annotatR/reference/at_canvas_proxy.md),
[`at_canvas_set_annotations()`](https://cttir.github.io/annotatR/reference/at_canvas_set_annotations.md),
[`at_canvas_set_band()`](https://cttir.github.io/annotatR/reference/at_canvas_set_band.md),
[`at_canvas_set_overlay()`](https://cttir.github.io/annotatR/reference/at_canvas_set_overlay.md),
[`at_canvas_set_tool()`](https://cttir.github.io/annotatR/reference/at_canvas_set_tool.md),
[`at_tile_source()`](https://cttir.github.io/annotatR/reference/at_tile_source.md),
[`renderAtCanvas()`](https://cttir.github.io/annotatR/reference/renderAtCanvas.md)
