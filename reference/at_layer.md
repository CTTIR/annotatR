# Create a layer

Create a layer

## Usage

``` r
at_layer(
  name,
  labels = character(),
  style = at_style(),
  ...,
  call = rlang::caller_env()
)
```

## Arguments

- name:

  Single string layer name (unique within a project).

- labels:

  Character vector; the controlled label vocabulary for the layer.

- style:

  An `annot_style`, from
  [`at_style()`](https://cttir.github.io/annotatR/reference/at_style.md).

- ...:

  Additional named metadata stored on the layer.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with no ROIs and a resolved colour mapping.

## See also

[`at_style()`](https://cttir.github.io/annotatR/reference/at_style.md),
[`at_layer_add()`](https://cttir.github.io/annotatR/reference/at_layer_add.md)

Other layers:
[`at_layer_add()`](https://cttir.github.io/annotatR/reference/at_layer_add.md),
[`at_layer_n()`](https://cttir.github.io/annotatR/reference/at_layer_n.md),
[`at_layer_remove()`](https://cttir.github.io/annotatR/reference/at_layer_remove.md),
[`at_layer_rois()`](https://cttir.github.io/annotatR/reference/at_layer_rois.md),
[`at_style()`](https://cttir.github.io/annotatR/reference/at_style.md)

## Examples

``` r
lyr <- at_layer("tumour", labels = c("tumour", "stroma"))
at_layer_n(lyr)
#> [1] 0
```
