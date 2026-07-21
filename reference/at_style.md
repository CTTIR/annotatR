# Layer style

Construct a style specification for an
[annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

## Usage

``` r
at_style(
  colour = NULL,
  fill_alpha = 0.3,
  stroke_width = 2,
  visible = TRUE,
  locked = FALSE,
  z = 1L,
  call = rlang::caller_env()
)
```

## Arguments

- colour:

  Either `NULL` (default; the Okabe-Ito colourblind-safe palette is
  cycled over the layer's labels), a single colour recycled across
  labels, or a named character vector mapping labels to colours. The
  style is stored with the resolved mapping so colours are stable across
  sessions.

- fill_alpha:

  Fill opacity in `[0, 1]`. Default `0.3`.

- stroke_width:

  Stroke width in pixels. Default `2`.

- visible:

  Logical; whether the layer is drawn. Default `TRUE`.

- locked:

  Logical; whether the layer is protected from edits. Default `FALSE`.

- z:

  Integer draw order (higher is drawn later, on top). Affects mask
  overlap resolution. Default `1`.

- call:

  The calling environment, for error reporting.

## Value

A named list of class `annot_style`.

## See also

Other layers:
[`at_layer()`](https://cttir.github.io/annotatR/reference/at_layer.md),
[`at_layer_add()`](https://cttir.github.io/annotatR/reference/at_layer_add.md),
[`at_layer_n()`](https://cttir.github.io/annotatR/reference/at_layer_n.md),
[`at_layer_remove()`](https://cttir.github.io/annotatR/reference/at_layer_remove.md),
[`at_layer_rois()`](https://cttir.github.io/annotatR/reference/at_layer_rois.md)

## Examples

``` r
at_style(fill_alpha = 0.5, z = 2)
#> $colour
#> NULL
#> 
#> $fill_alpha
#> [1] 0.5
#> 
#> $stroke_width
#> [1] 2
#> 
#> $visible
#> [1] TRUE
#> 
#> $locked
#> [1] FALSE
#> 
#> $z
#> [1] 2
#> 
#> attr(,"class")
#> [1] "annot_style"
```
