# Set operations on ROIs

Combine ROIs geometrically. Each accepts several
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
via `...`, or a single
[annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md).
Multi-part results are returned as one ROI with `MULTIPOLYGON` geometry
(the return type is always a single
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)).

## Usage

``` r
at_roi_union(..., call = rlang::caller_env())

at_roi_intersect(..., call = rlang::caller_env())

at_roi_difference(..., call = rlang::caller_env())

at_roi_symdiff(..., call = rlang::caller_env())
```

## Arguments

- ...:

  Two or more
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md),
  or a single
  [annot_layer](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A single
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with `source = "derived"`.

## See also

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
[`at_roi_simplify()`](https://cttir.github.io/annotatR/reference/at_roi_simplify.md),
[`at_rois_overlap()`](https://cttir.github.io/annotatR/reference/at_rois_overlap.md),
[`at_snap()`](https://cttir.github.io/annotatR/reference/at_snap.md),
[`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md)

## Examples

``` r
a <- at_roi_rect(0, 0, 6, 6, label = "x")
b <- at_roi_rect(4, 4, 10, 10, label = "x")
at_roi_area(at_roi_intersect(a, b))
#> [1] 4
```
