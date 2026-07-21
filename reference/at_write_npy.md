# Write a mask to a NumPy `.npy` file

Write an `annot_mask` as a lossless integer NumPy array, for interchange
with Python tools. A `<path>.legend.json` sidecar (value -\> label) is
written alongside so the array stays self-describing. Unlike
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
values are stored raw (no bit-depth normalisation), so bitfield artefact
masks survive intact.

## Usage

``` r
at_write_npy(
  mask,
  path,
  dtype = c("int32", "uint8", "int16"),
  transpose = FALSE,
  legend = TRUE,
  overwrite = FALSE,
  call = rlang::caller_env()
)
```

## Arguments

- mask:

  An `annot_mask`.

- path:

  Output file path.

- dtype:

  NumPy integer dtype: `"int32"` (default, wide enough for bitfield
  codes), `"uint8"`, or `"int16"`.

- transpose:

  Logical; write the transpose, i.e. numpy shape `(width, height)` =
  `[x, y]`, matching tools that store the native cube order (e.g.
  TIVITA/HyperGui). Default `FALSE` writes the standard image convention
  `(height, width)`.

- legend:

  Logical; also write a `<path>.legend.json` sidecar. Default `TRUE`.

- overwrite:

  Logical; overwrite an existing file. Default `FALSE`.

- call:

  The calling environment, for error reporting.

## Value

The output path, invisibly.

## See also

[`at_read_npy()`](https://cttir.github.io/annotatR/reference/at_read_npy.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md)

Other masks:
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_agreement()`](https://cttir.github.io/annotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/annotatR/reference/at_mask_derive.md),
[`at_mask_legend()`](https://cttir.github.io/annotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/annotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
[`at_read_npy()`](https://cttir.github.io/annotatR/reference/at_read_npy.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/annotatR/reference/at_write_masks.md)

## Examples

``` r
m <- at_mask(at_example_project(), "labelled")
f <- tempfile(fileext = ".npy")
at_write_npy(m, f)
```
