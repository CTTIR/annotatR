# Check the geometry of every ROI in a project

Check the geometry of every ROI in a project

## Usage

``` r
at_check_geometry(project, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `roi_id` (character), `issue` (character), `severity`
(character, `"error"`/`"warning"`), and `fixable` (logical). Detected
issues: self-intersection, invalid geometry, zero area, degenerate
rings, out-of-bounds vertices, duplicate consecutive vertices, ring
orientation, and `NA` coordinates. A 0-row tibble when all geometry is
valid.

## See also

[`at_fix_geometry()`](https://cttir.github.io/annotatR/reference/at_fix_geometry.md),
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)

Other geometry:
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
at_check_geometry(at_example_project())
#> # A tibble: 0 × 4
#> # ℹ 4 variables: roi_id <chr>, issue <chr>, severity <chr>, fixable <lgl>
```
