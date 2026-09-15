# Launch the batch annotation application

A launcher around
[`at_app()`](https://cttir.github.io/annotatR/reference/at_app.md): it
builds the app object from explicit arguments and runs it. Nothing is
exchanged through global options.

## Usage

``` r
at_annotate(
  x = NULL,
  labels = character(),
  layers = NULL,
  out_dir = NULL,
  launch.browser = TRUE,
  port = NULL,
  ...,
  call = rlang::caller_env()
)
```

## Arguments

- x:

  What to annotate: an
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  a character vector of image paths, a directory of images, or `NULL`
  (opens the bundled example session).

- labels:

  Character vector of the global label vocabulary.

- layers:

  An
  [annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  a list of them, or `NULL`. Applied as a template to every image.

- out_dir:

  Directory for autosave and exports.

- launch.browser:

  Passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

- port:

  Passed to
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html).

- ...:

  Passed to
  [`at_app()`](https://cttir.github.io/annotatR/reference/at_app.md)
  (`control`, `read_only`, `view`).

- call:

  The calling environment, for error reporting.

## Value

Invisible `NULL`. Launches a Shiny application; called for side effects.

## See also

[`at_app()`](https://cttir.github.io/annotatR/reference/at_app.md)

Other shiny:
[`atCanvasOutput()`](https://cttir.github.io/annotatR/reference/atCanvasOutput.md),
[`at_app()`](https://cttir.github.io/annotatR/reference/at_app.md),
[`at_canvas()`](https://cttir.github.io/annotatR/reference/at_canvas.md),
[`at_canvas_fit()`](https://cttir.github.io/annotatR/reference/at_canvas_fit.md),
[`at_canvas_proxy()`](https://cttir.github.io/annotatR/reference/at_canvas_proxy.md),
[`at_canvas_set_annotations()`](https://cttir.github.io/annotatR/reference/at_canvas_set_annotations.md),
[`at_canvas_set_band()`](https://cttir.github.io/annotatR/reference/at_canvas_set_band.md),
[`at_canvas_set_overlay()`](https://cttir.github.io/annotatR/reference/at_canvas_set_overlay.md),
[`at_canvas_set_selection()`](https://cttir.github.io/annotatR/reference/at_canvas_set_selection.md),
[`at_canvas_set_tool()`](https://cttir.github.io/annotatR/reference/at_canvas_set_tool.md),
[`at_tile_source()`](https://cttir.github.io/annotatR/reference/at_tile_source.md),
[`renderAtCanvas()`](https://cttir.github.io/annotatR/reference/renderAtCanvas.md)

## Examples

``` r
# \donttest{
if (interactive()) {
  at_annotate(at_example_session(5))
}
# }
```
