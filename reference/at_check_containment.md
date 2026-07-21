# Check cross-layer containment

Report ROIs in a constrained layer that fall outside their container
region. A layer declares the constraint through its metadata, e.g.
`at_layer("state", within = list(layer = "anatomy", label = "wound"))`;
then every ROI in `state` must be spatially covered by the union of the
`anatomy` layer's `wound` ROIs. This enforces the annotation rule that a
class is painted only inside its region of interest. The report mirrors
the shape of
[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md).

## Usage

``` r
at_check_containment(project, tol = 0, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- tol:

  Non-negative slack, in level-0 pixels, by which the container is grown
  before testing, to tolerate sub-pixel tracing overhang. Default `0`.

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `roi_id`, `layer`, `issue`, `severity` (`"warning"` for an
ROI outside its container, `"error"` for a missing/empty container), and
`fixable` (always `FALSE`). A 0-row tibble when every constrained ROI is
contained, or when no layer declares a `within` constraint.

## See also

[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md),
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)

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
[`at_roi_ring()`](https://cttir.github.io/annotatR/reference/at_roi_ring.md),
[`at_roi_setops`](https://cttir.github.io/annotatR/reference/at_roi_setops.md),
[`at_roi_simplify()`](https://cttir.github.io/annotatR/reference/at_roi_simplify.md),
[`at_rois_overlap()`](https://cttir.github.io/annotatR/reference/at_rois_overlap.md),
[`at_snap()`](https://cttir.github.io/annotatR/reference/at_snap.md),
[`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md)

## Examples

``` r
anatomy <- at_layer_add(at_layer("anatomy", labels = "wound"),
                        at_roi_rect(2, 2, 8, 8, label = "wound"))
state <- at_layer("state", labels = "injury",
                  within = list(layer = "anatomy", label = "wound"))
state <- at_layer_add(state, at_roi_rect(0, 0, 4, 4, label = "injury"))
at_check_containment(at_project(at_example_image("cube"), list(anatomy, state)))
#> # A tibble: 1 × 5
#>   roi_id        layer issue                                     severity fixable
#>   <chr>         <chr> <chr>                                     <chr>    <lgl>  
#> 1 roi_000000002 state ROI is not contained in layer 'anatomy' … warning  FALSE  
```
