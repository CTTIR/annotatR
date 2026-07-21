# Query the ROIs of a project

Return a tidy table of ROIs, optionally filtered by layer and/or label.

## Usage

``` r
at_rois(project, layer = NULL, label = NULL, call = rlang::caller_env())
```

## Arguments

- project:

  An
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- layer:

  Optional single layer name to filter to.

- label:

  Optional character vector of labels to filter to.

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with one row per ROI and, in this exact order, the columns:

- `roi_id`:

  Unique identifier (character).

- `layer`:

  Layer name (character).

- `label`:

  Class label (character).

- `geom_type`:

  Geometry type, e.g. `"POLYGON"` (character).

- `level`:

  Reference pyramid level (integer).

- `area_px`:

  Area in level-0 pixels (double); `NA` for points/lines.

- `centroid_x`,`centroid_y`:

  Centroid at level 0 (double).

- `n_vertices`:

  Vertex count (integer).

- `created`,`modified`:

  Timestamps (POSIXct).

- `author`:

  Author (character).

- `source`:

  Provenance source (character).

- `geometry`:

  The `sf` geometry column (`sfc`), at level 0.

Returns a 0-row tibble with these columns if no ROIs match.

## Details

Coordinates in the `geometry` column, together with `area_px` and the
centroid, are expressed at pyramid level 0; the `level` column records
the level at which each ROI was originally defined.

## See also

[`at_layers()`](https://cttir.github.io/annotatR/reference/at_layers.md),
[`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md)

Other projects:
[`at_add_layer()`](https://cttir.github.io/annotatR/reference/at_add_layer.md),
[`at_add_roi()`](https://cttir.github.io/annotatR/reference/at_add_roi.md),
[`at_example_project()`](https://cttir.github.io/annotatR/reference/at_example_project.md),
[`at_layers()`](https://cttir.github.io/annotatR/reference/at_layers.md),
[`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md),
[`at_remove_layer()`](https://cttir.github.io/annotatR/reference/at_remove_layer.md),
[`at_remove_roi()`](https://cttir.github.io/annotatR/reference/at_remove_roi.md),
[`at_summary()`](https://cttir.github.io/annotatR/reference/at_summary.md),
[`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md)

## Examples

``` r
# proj <- at_example_project()
# at_rois(proj)
```
