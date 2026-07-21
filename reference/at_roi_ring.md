# Ring (annulus) along an ROI margin

Build a band straddling an ROI's boundary – the natural shape for a
"penumbra" region along an injury or wound margin. The ring extends
`outer` units outside the boundary and `inner` units inside it, formed
as the set difference of the outward and inward buffers.

## Usage

``` r
at_roi_ring(
  roi,
  outer,
  inner = 0,
  label = roi$label,
  call = rlang::caller_env()
)
```

## Arguments

- roi:

  An
  [annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- outer:

  Non-negative outward width (dilation) of the ring.

- inner:

  Non-negative inward width (erosion) of the ring. Default `0`, a purely
  external band.

- label:

  Label for the derived ring ROI. Default the source ROI's label.

- call:

  The calling environment, for error reporting.

## Value

A derived
[annot_roi](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
(an annulus) with `source = "derived"`.

## See also

[`at_roi_buffer()`](https://cttir.github.io/annotatR/reference/at_roi_buffer.md),
[`at_roi_difference()`](https://cttir.github.io/annotatR/reference/at_roi_setops.md)

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
[`at_roi_setops`](https://cttir.github.io/annotatR/reference/at_roi_setops.md),
[`at_roi_simplify()`](https://cttir.github.io/annotatR/reference/at_roi_simplify.md),
[`at_rois_overlap()`](https://cttir.github.io/annotatR/reference/at_rois_overlap.md),
[`at_snap()`](https://cttir.github.io/annotatR/reference/at_snap.md),
[`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md)

## Examples

``` r
inj <- at_roi_rect(10, 10, 20, 20, label = "injury")
at_roi_ring(inj, outer = 3, label = "penumbra")
#> <annot_roi> penumbra (POLYGON)
#> id: "roi_000000067"  |  level: 0  |  source: derived
#> bbox: [7, 7] - [23, 23]
```
