# Agreement between two masks

Per-class Dice and Jaccard (IoU) plus an overall accuracy and Cohen's
kappa, comparing a reference mask `a` against a second mask `b` (e.g. an
annotatR mask against a `.npy` ground truth, or two annotators). Classes
are matched by integer value, so both masks must use the same class
codebook.

## Usage

``` r
at_mask_agreement(
  a,
  b,
  background = 0L,
  labels = NULL,
  call = rlang::caller_env()
)
```

## Arguments

- a:

  Reference `annot_mask` or integer matrix.

- b:

  Comparison `annot_mask` or integer matrix, same dimensions as `a`.

- background:

  Integer value treated as unlabeled/background and excluded from the
  per-class rows (still counted for overall accuracy/kappa). Default
  `0`.

- labels:

  Optional named vector or legend tibble (`value`, `label`) overriding
  the reference legend for class labels.

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with one row per class: `value`, `label`, `n_true`, `n_pred`, `tp`,
`fp`, `fn`, `dice`, `iou`. The `overall` attribute is a list of
`accuracy`, `kappa`, `mean_dice`, `mean_iou`, and `n_px`.

## See also

[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_read_npy()`](https://cttir.github.io/annotatR/reference/at_read_npy.md)

Other masks:
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md),
[`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
[`at_mask_derive()`](https://cttir.github.io/annotatR/reference/at_mask_derive.md),
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
m <- at_mask(at_example_project(), "multiclass")
ag <- at_mask_agreement(m, m)
attr(ag, "overall")$kappa
#> [1] 1
```
