# annotatR S3 classes

annotatR represents annotations with a small set of S3 classes. This
page collects them so they can be cross-referenced from the
documentation.

- `annot_image`:

  A backend-agnostic image handle holding metadata and a lazy tile
  accessor. Created by
  [`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md)
  or
  [`at_example_image()`](https://cttir.github.io/annotatR/reference/at_example_image.md).

- `annot_roi`:

  A single region of interest: an `sf` geometry in image pixel
  coordinates at a declared pyramid level. Created by the `at_roi_*()`
  constructors.

- `annot_layer`:

  A named collection of ROIs sharing a label vocabulary and a visual
  style. Created by
  [`at_layer()`](https://cttir.github.io/annotatR/reference/at_layer.md).

- `annot_project`:

  An image plus a named set of layers and provenance. Created by
  [`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md).

- `annot_session`:

  A resumable batch-annotation session over a queue of images. Created
  by
  [`at_session()`](https://cttir.github.io/annotatR/reference/at_session.md).

- `annot_mask`:

  A rasterised mask: a labelled or binary integer matrix with a legend.
  Created by
  [`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md).

- `annot_style`:

  A layer style specification. Created by
  [`at_style()`](https://cttir.github.io/annotatR/reference/at_style.md).

- `annot_summary`:

  A compact per-label project summary. Created by
  [`at_summary()`](https://cttir.github.io/annotatR/reference/at_summary.md).

## See also

[`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md),
[`at_layer()`](https://cttir.github.io/annotatR/reference/at_layer.md)

Other images:
[`at_bands()`](https://cttir.github.io/annotatR/reference/at_bands.md),
[`at_dims()`](https://cttir.github.io/annotatR/reference/at_dims.md),
[`at_example_image()`](https://cttir.github.io/annotatR/reference/at_example_image.md),
[`at_is_pyramidal()`](https://cttir.github.io/annotatR/reference/at_is_pyramidal.md),
[`at_is_spectral()`](https://cttir.github.io/annotatR/reference/at_is_spectral.md),
[`at_meta()`](https://cttir.github.io/annotatR/reference/at_meta.md),
[`at_n_bands()`](https://cttir.github.io/annotatR/reference/at_n_bands.md),
[`at_n_levels()`](https://cttir.github.io/annotatR/reference/at_n_levels.md),
[`at_pixel_size()`](https://cttir.github.io/annotatR/reference/at_pixel_size.md),
[`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md),
[`at_wavelengths()`](https://cttir.github.io/annotatR/reference/at_wavelengths.md)
