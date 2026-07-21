# Derive a training mask from layer masks

Combine rasterised layer masks into the derived training mask
`state WHERE anatomy == keep_label AND artefact == 0 AND state != background`.
This is the cross-layer operation the four-layer HSI scheme relies on:
it keeps a state (class) label only where the anatomy layer marks the
region of interest, no artefact bit is set, and the state is actually
labelled.

## Usage

``` r
at_mask_derive(
  state,
  anatomy,
  artefact = NULL,
  keep_label = "wound",
  background = 0L,
  call = rlang::caller_env()
)
```

## Arguments

- state:

  An `annot_mask` of state (class) codes.

- anatomy:

  An `annot_mask` of anatomy codes, sharing `state`'s dimensions and
  level.

- artefact:

  Optional `annot_mask` (bitfield); pixels with any artefact bit set are
  dropped. `NULL` (default) applies no artefact exclusion.

- keep_label:

  The anatomy label whose region is kept (e.g. `"wound"`).

- background:

  Integer background/unlabeled value. Default `0`.

- call:

  The calling environment, for error reporting.

## Value

An `annot_mask` (multiclass) of the surviving state codes, with the
state legend restricted to those classes and pixel counts recomputed.

## See also

[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md)

Other masks:
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_agreement()`](https://cttir.github.io/annotatR/reference/at_mask_agreement.md),
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_legend()`](https://cttir.github.io/annotatR/reference/at_mask_legend.md),
[`at_mask_preview()`](https://cttir.github.io/annotatR/reference/at_mask_preview.md),
[`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md),
[`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md),
[`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md),
[`at_read_npy()`](https://cttir.github.io/annotatR/reference/at_read_npy.md),
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md),
[`at_write_masks()`](https://cttir.github.io/annotatR/reference/at_write_masks.md),
[`at_write_npy()`](https://cttir.github.io/annotatR/reference/at_write_npy.md)

## Examples

``` r
proj <- at_example_project()
# A single-layer project derives trivially; the four-layer HSI workflow passes
# separate anatomy/state/artefact masks. See the masks vignette.
m <- at_mask(proj, "multiclass")
at_mask_derive(m, m, keep_label = at_mask_legend(m)$label[1])
#> <annot_mask> multiclass  |  512 x 512 px  |  level 0
#> values: 1
#> # A tibble: 1 × 6
#>   value label  layer   roi_id  n_px colour 
#>   <int> <chr>  <chr>   <chr>  <int> <chr>  
#> 1     1 tumour regions NA     19600 #999999
```
