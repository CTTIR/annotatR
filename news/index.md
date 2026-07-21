# Changelog

## annotatR 0.0.1

Initial development release.

### Images and backends

- [`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md)
  reads an image into a lightweight `annot_image` handle, auto-detecting
  the backend.
  [`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md)
  is the universal `[y, x, band]` tile accessor. Six backends ship
  (`raster`, `tiff`, `ometiff`, `cuvis`, `tivita`, `envi`); register
  more with
  [`at_backend_register()`](https://cttir.github.io/annotatR/reference/at_backend_register.md).
- The `tivita` backend reads bare Diaspective Vision TIVITA
  `*_SpecCube.dat` cubes directly (big-endian float32, 640x480x100,
  500-995 nm), in addition to ENVI-conformant exports; such cubes also
  auto-detect.
- Accessors:
  [`at_dims()`](https://cttir.github.io/annotatR/reference/at_dims.md),
  [`at_n_levels()`](https://cttir.github.io/annotatR/reference/at_n_levels.md),
  [`at_n_bands()`](https://cttir.github.io/annotatR/reference/at_n_bands.md),
  [`at_bands()`](https://cttir.github.io/annotatR/reference/at_bands.md),
  [`at_wavelengths()`](https://cttir.github.io/annotatR/reference/at_wavelengths.md),
  [`at_is_spectral()`](https://cttir.github.io/annotatR/reference/at_is_spectral.md),
  [`at_is_pyramidal()`](https://cttir.github.io/annotatR/reference/at_is_pyramidal.md),
  [`at_pixel_size()`](https://cttir.github.io/annotatR/reference/at_pixel_size.md),
  [`at_meta()`](https://cttir.github.io/annotatR/reference/at_meta.md).

### Regions of interest and geometry

- Constructors
  [`at_roi_point()`](https://cttir.github.io/annotatR/reference/at_roi_point.md),
  [`at_roi_rect()`](https://cttir.github.io/annotatR/reference/at_roi_rect.md),
  [`at_roi_circle()`](https://cttir.github.io/annotatR/reference/at_roi_circle.md),
  [`at_roi_ellipse()`](https://cttir.github.io/annotatR/reference/at_roi_ellipse.md),
  [`at_roi_polygon()`](https://cttir.github.io/annotatR/reference/at_roi_polygon.md),
  [`at_roi_freehand()`](https://cttir.github.io/annotatR/reference/at_roi_freehand.md),
  [`at_roi_from_sf()`](https://cttir.github.io/annotatR/reference/at_roi_from_sf.md),
  storing validated `sf` geometry in image pixel coordinates.
- Measures and transforms:
  [`at_roi_area()`](https://cttir.github.io/annotatR/reference/at_roi_area.md),
  [`at_roi_centroid()`](https://cttir.github.io/annotatR/reference/at_roi_centroid.md),
  [`at_roi_bbox()`](https://cttir.github.io/annotatR/reference/at_roi_bbox.md),
  [`at_roi_buffer()`](https://cttir.github.io/annotatR/reference/at_roi_buffer.md),
  [`at_roi_simplify()`](https://cttir.github.io/annotatR/reference/at_roi_simplify.md),
  [`at_roi_rescale()`](https://cttir.github.io/annotatR/reference/at_roi_rescale.md),
  [`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md),
  [`at_flip_y()`](https://cttir.github.io/annotatR/reference/at_flip_y.md),
  [`at_snap()`](https://cttir.github.io/annotatR/reference/at_snap.md),
  [`at_clamp()`](https://cttir.github.io/annotatR/reference/at_clamp.md).
- Set operations
  [`at_roi_union()`](https://cttir.github.io/annotatR/reference/at_roi_setops.md)/[`intersect()`](https://rdrr.io/r/base/sets.html)/`difference()`/`symdiff()`,
  [`at_roi_ring()`](https://cttir.github.io/annotatR/reference/at_roi_ring.md)
  (an annulus straddling an ROI margin, e.g. a penumbra band),
  predicates
  [`at_roi_contains()`](https://cttir.github.io/annotatR/reference/at_roi_contains.md)/`overlaps()`/`distance()`/[`at_rois_overlap()`](https://cttir.github.io/annotatR/reference/at_rois_overlap.md),
  and validation
  [`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md)
  /
  [`at_fix_geometry()`](https://cttir.github.io/annotatR/reference/at_fix_geometry.md).
- [`at_check_containment()`](https://cttir.github.io/annotatR/reference/at_check_containment.md)
  reports ROIs that fall outside a container region declared by a
  layer’s `within` metadata (e.g. state painted only inside the anatomy
  `wound`), enforcing the annotation guideline’s containment rule.

### Layers, projects, and sessions

- [`at_layer()`](https://cttir.github.io/annotatR/reference/at_layer.md),
  [`at_style()`](https://cttir.github.io/annotatR/reference/at_style.md),
  [`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md),
  and their pure mutators
  ([`at_add_layer()`](https://cttir.github.io/annotatR/reference/at_add_layer.md),
  [`at_add_roi()`](https://cttir.github.io/annotatR/reference/at_add_roi.md),
  [`at_remove_layer()`](https://cttir.github.io/annotatR/reference/at_remove_layer.md),
  [`at_remove_roi()`](https://cttir.github.io/annotatR/reference/at_remove_roi.md)),
  with the
  [`at_rois()`](https://cttir.github.io/annotatR/reference/at_rois.md)
  query contract,
  [`at_layers()`](https://cttir.github.io/annotatR/reference/at_layers.md),
  [`at_validate()`](https://cttir.github.io/annotatR/reference/at_validate.md),
  and
  [`at_summary()`](https://cttir.github.io/annotatR/reference/at_summary.md).
- Resumable sessions:
  [`at_session()`](https://cttir.github.io/annotatR/reference/at_session.md),
  [`at_next()`](https://cttir.github.io/annotatR/reference/at_next.md)/[`at_prev()`](https://cttir.github.io/annotatR/reference/at_prev.md)/[`at_goto()`](https://cttir.github.io/annotatR/reference/at_goto.md),
  [`at_current()`](https://cttir.github.io/annotatR/reference/at_current.md),
  [`at_set_status()`](https://cttir.github.io/annotatR/reference/at_set_status.md),
  [`at_manifest()`](https://cttir.github.io/annotatR/reference/at_manifest.md),
  [`at_resume()`](https://cttir.github.io/annotatR/reference/at_resume.md).

### Masks

- [`at_mask()`](https://cttir.github.io/annotatR/reference/at_mask.md)
  produces binary, labelled, or multi-class integer masks with a
  documented pixel-coverage contract, six overlap policies, and a
  self-describing legend. A `values` argument pins labels to explicit
  integer codes, and the `"bitor"` overlap policy bitwise-ORs
  overlapping values to build bitfield masks (e.g. an artefact layer
  where a pixel is `specular | blood`). Helpers:
  [`at_mask_stats()`](https://cttir.github.io/annotatR/reference/at_mask_stats.md),
  [`at_mask_boundary()`](https://cttir.github.io/annotatR/reference/at_mask_boundary.md),
  [`at_mask_preview()`](https://cttir.github.io/annotatR/reference/at_mask_preview.md),
  [`at_mask_stack()`](https://cttir.github.io/annotatR/reference/at_mask_stack.md).
- [`at_mask_derive()`](https://cttir.github.io/annotatR/reference/at_mask_derive.md)
  combines layer masks into a derived training mask
  (`state WHERE anatomy == keep AND artefact == 0 AND state != background`).
- [`at_mask_agreement()`](https://cttir.github.io/annotatR/reference/at_mask_agreement.md)
  scores two masks with per-class Dice / IoU and an overall accuracy and
  Cohen’s kappa (e.g. against a `.npy` ground truth).
- [`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md)
  writes TIFF/PNG/RDS with a sidecar JSON legend;
  [`at_read_mask()`](https://cttir.github.io/annotatR/reference/at_read_mask.md)
  polygonises a mask back into editable ROIs.
  [`at_write_npy()`](https://cttir.github.io/annotatR/reference/at_write_npy.md)
  /
  [`at_read_npy()`](https://cttir.github.io/annotatR/reference/at_read_npy.md)
  losslessly interchange integer masks (incl. bitfields) with NumPy
  `.npy`, the format used by external HSI annotation tools.

### Extraction, plots, interchange, and batch

- Tile-wise
  [`at_extract()`](https://cttir.github.io/annotatR/reference/at_extract.md),
  [`at_extract_spectrum()`](https://cttir.github.io/annotatR/reference/at_extract_spectrum.md),
  [`at_extract_pixels()`](https://cttir.github.io/annotatR/reference/at_extract_pixels.md).
- ggplot2 plots
  [`at_plot_image()`](https://cttir.github.io/annotatR/reference/at_plot_image.md),
  [`at_plot_project()`](https://cttir.github.io/annotatR/reference/at_plot_project.md),
  [`at_plot_overlay()`](https://cttir.github.io/annotatR/reference/at_plot_overlay.md),
  [`at_plot_mask()`](https://cttir.github.io/annotatR/reference/at_plot_mask.md),
  [`at_plot_spectrum()`](https://cttir.github.io/annotatR/reference/at_plot_spectrum.md),
  [`at_plot_summary()`](https://cttir.github.io/annotatR/reference/at_plot_summary.md).
- Round-tripping I/O:
  [`at_write_geojson()`](https://cttir.github.io/annotatR/reference/at_write_geojson.md)/[`at_read_geojson()`](https://cttir.github.io/annotatR/reference/at_read_geojson.md),
  [`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md)/[`at_read_qupath()`](https://cttir.github.io/annotatR/reference/at_read_qupath.md),
  [`at_write_rois_csv()`](https://cttir.github.io/annotatR/reference/at_write_rois_csv.md)/
  [`at_read_rois_csv()`](https://cttir.github.io/annotatR/reference/at_read_rois_csv.md),
  project/session RDS.
- Whole-session
  [`at_export_all()`](https://cttir.github.io/annotatR/reference/at_export_all.md),
  [`at_summary_table()`](https://cttir.github.io/annotatR/reference/at_summary_table.md),
  [`at_batch_apply()`](https://cttir.github.io/annotatR/reference/at_batch_apply.md),
  [`at_batch_check_geometry()`](https://cttir.github.io/annotatR/reference/at_batch_check_geometry.md).

### Application

- [`at_annotate()`](https://cttir.github.io/annotatR/reference/at_annotate.md)
  launches a resumable, keyboard-first batch annotation app with live
  mask preview, built on `shiny` and a deep-zoom canvas widget.
