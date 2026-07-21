# Distance between two ROIs

Distance between two ROIs

## Usage

``` r
at_roi_distance(roi1, roi2, call = rlang::caller_env())
```

## Arguments

- roi1, roi2:

  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
  objects.

- call:

  The calling environment, for error reporting.

## Value

A numeric scalar distance in level-0 pixels.

## See also

Other geometry:
[`at_check_containment()`](https://cttir.github.io/annotatR/reference/at_check_containment.md),
[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md),
[`at_clamp()`](https://cttir.github.io/annotatR/reference/at_clamp.md),
[`at_fix_geometry()`](https://cttir.github.io/annotatR/reference/at_fix_geometry.md),
[`at_flip_y()`](https://cttir.github.io/annotatR/reference/at_flip_y.md),
[`at_roi_buffer()`](https://cttir.github.io/annotatR/reference/at_roi_buffer.md),
[`at_roi_contains()`](https://cttir.github.io/annotatR/reference/at_roi_contains.md),
[`at_roi_overlaps()`](https://cttir.github.io/annotatR/reference/at_roi_overlaps.md),
[`at_roi_rescale()`](https://cttir.github.io/annotatR/reference/at_roi_rescale.md),
[`at_roi_ring()`](https://cttir.github.io/annotatR/reference/at_roi_ring.md),
[`at_roi_setops`](https://cttir.github.io/annotatR/reference/at_roi_setops.md),
[`at_roi_simplify()`](https://cttir.github.io/annotatR/reference/at_roi_simplify.md),
[`at_rois_overlap()`](https://cttir.github.io/annotatR/reference/at_rois_overlap.md),
[`at_snap()`](https://cttir.github.io/annotatR/reference/at_snap.md),
[`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md)
