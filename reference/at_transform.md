# Transform an ROI between pyramid levels using real image dimensions

Unlike
[`at_roi_rescale()`](https://cttir.github.io/annotatR/reference/at_roi_rescale.md)
(which assumes a power-of-two pyramid), this uses the actual level
dimensions of an
[annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
so it is exact for pyramids with any downsampling ratio.

## Usage

``` r
at_transform(roi, from_level, to_level, img, call = rlang::caller_env())
```

## Arguments

- roi:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- from_level, to_level:

  Integer source and target pyramid levels.

- img:

  The
  [annot_image](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
  whose pyramid defines the level dimensions.

- call:

  The calling environment, for error reporting.

## Value

An
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with coordinates at `to_level`. Exactly invertible.

## See also

[`at_roi_rescale()`](https://cttir.github.io/annotatR/reference/at_roi_rescale.md)

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
[`at_roi_rescale()`](https://cttir.github.io/annotatR/reference/at_roi_rescale.md),
[`at_roi_ring()`](https://cttir.github.io/annotatR/reference/at_roi_ring.md),
[`at_roi_setops`](https://cttir.github.io/annotatR/reference/at_roi_setops.md),
[`at_roi_simplify()`](https://cttir.github.io/annotatR/reference/at_roi_simplify.md),
[`at_rois_overlap()`](https://cttir.github.io/annotatR/reference/at_rois_overlap.md),
[`at_snap()`](https://cttir.github.io/annotatR/reference/at_snap.md)

## Examples

``` r
img <- at_example_image("multiplex")
r <- at_roi_rect(0, 0, 100, 100, label = "a")
at_transform(r, from_level = 0, to_level = 2, img = img)
#> <annot_roi> a (POLYGON)
#> id: "roi_000000079"  |  level: 2  |  source: manual
#> bbox: [0, 0] - [25, 25]
```
