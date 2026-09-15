# Build the annotation app as a Shiny app object

Construct the batch annotation application from explicit inputs, without
launching a browser or touching global options. The result can be run
with [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html),
embedded in another Shiny application, or exercised in tests;
[`at_annotate()`](https://cttir.github.io/annotatR/reference/at_annotate.md)
is a launcher around it.

## Usage

``` r
at_app(
  input = NULL,
  session = NULL,
  control = "off",
  labels = character(),
  layers = NULL,
  out_dir = NULL,
  read_only = FALSE,
  view = NULL,
  ...,
  call = rlang::caller_env()
)
```

## Arguments

- input:

  What to annotate: an
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  a character vector of image paths, a directory of images, or `NULL`.

- session:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
  to resume. Supply `input` or `session`, not both; with neither, the
  bundled example session is used.

- control:

  `"off"` (default; no control service) or an `at_control_handle` from
  [`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md)
  whose session the app then displays and synchronises with.

- labels, layers, out_dir:

  Passed to
  [`at_session()`](https://cttir.github.io/annotatR/reference/at_session.md)
  when `input` is not a session.

- read_only:

  Logical; disable all annotation edits (view and inspect only).

- view:

  Optional initial band view, e.g.
  `list(operation = "rgb", bands = c(30, 20, 10))`.

- ...:

  Reserved; must be empty.

- call:

  The calling environment, for error reporting.

## Value

A `shiny.appobj`.

## See also

[`at_annotate()`](https://cttir.github.io/annotatR/reference/at_annotate.md),
[`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md)

Other shiny:
[`atCanvasOutput()`](https://cttir.github.io/annotatR/reference/atCanvasOutput.md),
[`at_annotate()`](https://cttir.github.io/annotatR/reference/at_annotate.md),
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
app <- at_app(session = at_example_session(2))
class(app)
#> [1] "shiny.appobj"
if (FALSE) { # \dontrun{
shiny::runApp(app)
} # }
```
