# Replace the annotations on a canvas

Replace the annotations on a canvas

## Usage

``` r
at_canvas_set_annotations(
  proxy,
  project,
  layer = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- proxy:

  An `atcanvas_proxy`.

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- layer:

  Optional layer filter.

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
[`at_canvas_set_band()`](https://cttir.github.io/annotatR/reference/at_canvas_set_band.md),
[`at_canvas_set_overlay()`](https://cttir.github.io/annotatR/reference/at_canvas_set_overlay.md),
[`at_canvas_set_tool()`](https://cttir.github.io/annotatR/reference/at_canvas_set_tool.md),
[`at_tile_source()`](https://cttir.github.io/annotatR/reference/at_tile_source.md),
[`renderAtCanvas()`](https://cttir.github.io/annotatR/reference/renderAtCanvas.md)
