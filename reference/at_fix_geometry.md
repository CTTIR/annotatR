# Repair the geometry of a project

Apply
[`sf::st_make_valid()`](https://r-spatial.github.io/sf/reference/valid.html)
to invalid ROIs (which also drops duplicate consecutive vertices) and
clamp out-of-bounds vertices into the image bounds, reporting what
changed.

## Usage

``` r
at_fix_geometry(project, verbose = TRUE, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- verbose:

  Logical; whether to report repairs. Default `TRUE`.

- call:

  The calling environment, for error reporting.

## Value

The
[annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
with repaired geometry. Repairs are reported via
[`cli::cli_inform()`](https://cli.r-lib.org/reference/cli_abort.html)
when `verbose` is `TRUE`. Issues that cannot be repaired (zero area,
degenerate, `NA` coordinates) are left in place and reported.

## See also

[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md)

Other geometry:
[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md),
[`at_clamp()`](https://cttir.github.io/annotatR/reference/at_clamp.md),
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
