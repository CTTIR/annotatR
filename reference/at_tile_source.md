# Build a tile-source descriptor for the canvas

Build a tile-source descriptor for the canvas

## Usage

``` r
at_tile_source(
  img,
  level_max = NULL,
  tile_size = 512L,
  embed = TRUE,
  call = rlang::caller_env()
)
```

## Arguments

- img:

  An
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- level_max:

  Optional maximum level to expose; the image maximum by default.

- tile_size:

  Tile size in pixels. Default `512`.

- embed:

  Logical; embed a downsampled base image as a data URI (for the
  self-contained canvas). Default `TRUE`.

- call:

  The calling environment, for error reporting.

## Value

A list describing the image for the widget: `width`, `height`,
`tileSize`, `minLevel`, `maxLevel`, `nBands`, and (when `embed`)
`dataUri`.

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
[`renderAtCanvas()`](https://cttir.github.io/annotatR/reference/renderAtCanvas.md)
