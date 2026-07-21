# Rasterise ROIs to a mask ("Schablone")

Produce a binary, labelled, or multi-class integer mask from
annotations. This is the package's core output artifact.

## Usage

``` r
at_mask(
  x,
  type = c("binary", "labelled", "multiclass"),
  layer = NULL,
  label = NULL,
  level = 0L,
  background = 0L,
  touches = FALSE,
  dims = NULL,
  overlap = c("last", "first", "max", "min", "error"),
  engine = c("stars", "terra"),
  call = rlang::caller_env()
)
```

## Arguments

- x:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  [annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  or
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- type:

  `"binary"` (a logical matrix), `"labelled"` (one integer id per ROI),
  or `"multiclass"` (one id per label class).

- layer:

  Optional layer name(s) to restrict to (projects only).

- label:

  Optional label(s) to restrict to.

- level:

  Integer pyramid level at which to rasterise. Default `0`.

- background:

  Integer background value. Default `0`.

- touches:

  Logical; see the coverage contract. Default `FALSE`.

- dims:

  Optional `c(width, height)`; taken from the image (projects) or the
  geometry bounding box otherwise.

- overlap:

  How overlapping ROIs resolve: `"last"` (later z-order wins, the
  default), `"first"`, `"max"`, `"min"`, or `"error"` (abort on any
  overlap).

- engine:

  `"stars"` (reference) or `"terra"` (accelerated, if installed); the
  two produce identical masks.

- call:

  The calling environment, for error reporting.

## Value

An `annot_mask`: a matrix (logical for `"binary"`, otherwise integer)
with attributes `legend` (a tibble with columns `value`, `label`,
`layer`, `roi_id`, `n_px`, `colour`), `level`, `dims`, `type`, and
`created`. An all-background mask of the correct dimensions is returned
when there are no ROIs.

## Details

**Pixel-coverage contract.** Pixel `(i, j)` covers the half-open square
`[j-1, j) x [i-1, i)` with `(0, 0)` at the top-left corner of the
top-left pixel; its centre is `(j - 0.5, i - 0.5)`. With
`touches = FALSE` (default) a pixel is included when its centre lies
inside the polygon; with `touches = TRUE` a pixel is included if the
polygon touches it at all. ROI coordinates use the image convention
(top-left origin, y down).

## See also

[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
[`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md)

Other masks:
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_legend()`](https://cttir.github.io/annotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/annotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/annotatR/reference/at_write_masks.md)

## Examples

``` r
proj <- at_example_project()
m <- at_mask(proj, type = "multiclass")
table(as.integer(m))
#> 
#>      0      1      2      3 
#> 135640  19600  72704  34200 
```
