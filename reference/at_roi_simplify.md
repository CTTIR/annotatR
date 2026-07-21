# Simplify an ROI

Simplify an ROI

## Usage

``` r
at_roi_simplify(roi, tolerance, call = rlang::caller_env())
```

## Arguments

- roi:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- tolerance:

  Non-negative Douglas-Peucker tolerance (`dTolerance`).

- call:

  The calling environment, for error reporting.

## Value

An
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with simplified geometry.

## See also

Other geometry:
[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md),
[`at_clamp()`](https://cttir.github.io/annotatR/reference/at_clamp.md),
[`at_fix_geometry()`](https://cttir.github.io/annotatR/reference/at_fix_geometry.md),
[`at_flip_y()`](https://cttir.github.io/annotatR/reference/at_flip_y.md),
[`at_roi_buffer()`](https://cttir.github.io/annotatR/reference/at_roi_buffer.md),
[`at_roi_contains()`](https://cttir.github.io/annotatR/reference/at_roi_contains.md),
[`at_roi_distance()`](https://cttir.github.io/annotatR/reference/at_roi_distance.md),
[`at_roi_overlaps()`](https://cttir.github.io/annotatR/reference/at_roi_overlaps.md),
[`at_roi_rescale()`](https://cttir.github.io/annotatR/reference/at_roi_rescale.md),
[`at_roi_setops`](https://cttir.github.io/annotatR/reference/at_roi_setops.md),
[`at_rois_overlap()`](https://cttir.github.io/annotatR/reference/at_rois_overlap.md),
[`at_snap()`](https://cttir.github.io/annotatR/reference/at_snap.md),
[`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md)

## Examples

``` r
at_roi_simplify(at_roi_circle(50, 50, 10, n_seg = 128, label = "a"), 1)
#> <annot_roi> a (POLYGON)
#> id: "roi_000000058"  |  level: 0  |  source: manual
#> bbox: [40, 40] - [60, 60]
```
