# Launch the batch annotation application

Launch the batch annotation application

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

  Reserved for future use.

- call:

  The calling environment, for error reporting.

## Value

Invisible `NULL`. Launches a Shiny application; called for side effects.

## See also

Other shiny:
[`atCanvasOutput()`](https://cttir.github.io/annotatR/reference/atCanvasOutput.md),
[`at_canvas()`](https://cttir.github.io/annotatR/reference/at_canvas.md),
[`at_canvas_fit()`](https://cttir.github.io/annotatR/reference/at_canvas_fit.md),
[`at_canvas_proxy()`](https://cttir.github.io/annotatR/reference/at_canvas_proxy.md),
[`at_canvas_set_annotations()`](https://cttir.github.io/annotatR/reference/at_canvas_set_annotations.md),
[`at_canvas_set_band()`](https://cttir.github.io/annotatR/reference/at_canvas_set_band.md),
[`at_canvas_set_overlay()`](https://cttir.github.io/annotatR/reference/at_canvas_set_overlay.md),
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
