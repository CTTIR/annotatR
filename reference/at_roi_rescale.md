# Rescale an ROI between pyramid levels

Transform an ROI's coordinates from one pyramid level to another,
assuming a power-of-two pyramid. For an exact transform against a real
image pyramid (which need not be power-of-two), use
[`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md)
with the
[annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

## Usage

``` r
at_roi_rescale(roi, from_level, to_level, call = rlang::caller_env())
```

## Arguments

- roi:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- from_level, to_level:

  Integer source and target pyramid levels.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with coordinates at `to_level` and its `level` field set to `to_level`.
The transform is exactly invertible.

## See also

[`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md)

Other geometry:
[`at_check_containment()`](https://cttir.github.io/annotatR/reference/at_check_containment.md),
[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md),
[`at_clamp()`](https://cttir.github.io/annotatR/reference/at_clamp.md),
[`at_fix_geometry()`](https://cttir.github.io/annotatR/reference/at_fix_geometry.md),
[`at_flip_y()`](https://cttir.github.io/annotatR/reference/at_flip_y.md),
[`at_roi_buffer()`](https://cttir.github.io/annotatR/reference/at_roi_buffer.md),
[`at_roi_contains()`](https://cttir.github.io/annotatR/reference/at_roi_contains.md),
[`at_roi_distance()`](https://cttir.github.io/annotatR/reference/at_roi_distance.md),
[`at_roi_overlaps()`](https://cttir.github.io/annotatR/reference/at_roi_overlaps.md),
[`at_roi_ring()`](https://cttir.github.io/annotatR/reference/at_roi_ring.md),
[`at_roi_setops`](https://cttir.github.io/annotatR/reference/at_roi_setops.md),
[`at_roi_simplify()`](https://cttir.github.io/annotatR/reference/at_roi_simplify.md),
[`at_rois_overlap()`](https://cttir.github.io/annotatR/reference/at_rois_overlap.md),
[`at_snap()`](https://cttir.github.io/annotatR/reference/at_snap.md),
[`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md)

## Examples

``` r
r <- at_roi_rect(0, 0, 100, 100, label = "a")
r2 <- at_roi_rescale(r, from_level = 0, to_level = 2)
identical(
  sf::st_coordinates(sf::st_geometry(r)),
  sf::st_coordinates(sf::st_geometry(at_roi_rescale(r2, 2, 0)))
)
#> [1] TRUE
```
