# annotatR 0.0.1

Initial development release.

## Images and backends

* `at_read_image()` reads an image into a lightweight `annot_image` handle,
  auto-detecting the backend. `at_tile()` is the universal `[y, x, band]` tile
  accessor. Six backends ship (`raster`, `tiff`, `ometiff`, `cuvis`, `tivita`,
  `envi`); register more with `at_backend_register()`.
* The `tivita` backend reads bare Diaspective Vision TIVITA `*_SpecCube.dat`
  cubes directly (big-endian float32, 640x480x100, 500-995 nm), in addition to
  ENVI-conformant exports; such cubes also auto-detect.
* Accessors: `at_dims()`, `at_n_levels()`, `at_n_bands()`, `at_bands()`,
  `at_wavelengths()`, `at_is_spectral()`, `at_is_pyramidal()`,
  `at_pixel_size()`, `at_meta()`.

## Regions of interest and geometry

* Constructors `at_roi_point()`, `at_roi_rect()`, `at_roi_circle()`,
  `at_roi_ellipse()`, `at_roi_polygon()`, `at_roi_freehand()`,
  `at_roi_from_sf()`, storing validated `sf` geometry in image pixel
  coordinates.
* Measures and transforms: `at_roi_area()`, `at_roi_centroid()`,
  `at_roi_bbox()`, `at_roi_buffer()`, `at_roi_simplify()`, `at_roi_rescale()`,
  `at_transform()`, `at_flip_y()`, `at_snap()`, `at_clamp()`.
* Set operations `at_roi_union()`/`intersect()`/`difference()`/`symdiff()`,
  `at_roi_ring()` (an annulus straddling an ROI margin, e.g. a penumbra band),
  predicates `at_roi_contains()`/`overlaps()`/`distance()`/`at_rois_overlap()`,
  and validation `at_check_geometry()` / `at_fix_geometry()`.
* `at_check_containment()` reports ROIs that fall outside a container region
  declared by a layer's `within` metadata (e.g. state painted only inside the
  anatomy `wound`), enforcing the annotation guideline's containment rule.

## Layers, projects, and sessions

* `at_layer()`, `at_style()`, `at_project()`, and their pure mutators
  (`at_add_layer()`, `at_add_roi()`, `at_remove_layer()`, `at_remove_roi()`),
  with the `at_rois()` query contract, `at_layers()`, `at_validate()`, and
  `at_summary()`.
* Resumable sessions: `at_session()`, `at_next()`/`at_prev()`/`at_goto()`,
  `at_current()`, `at_set_status()`, `at_manifest()`, `at_resume()`.

## Masks

* `at_mask()` produces binary, labelled, or multi-class integer masks with a
  documented pixel-coverage contract, six overlap policies, and a
  self-describing legend. A `values` argument pins labels to explicit integer
  codes, and the `"bitor"` overlap policy bitwise-ORs overlapping values to
  build bitfield masks (e.g. an artefact layer where a pixel is
  `specular | blood`). Helpers: `at_mask_stats()`, `at_mask_boundary()`,
  `at_mask_preview()`, `at_mask_stack()`.
* `at_mask_derive()` combines layer masks into a derived training mask
  (`state WHERE anatomy == keep AND artefact == 0 AND state != background`).
* `at_mask_agreement()` scores two masks with per-class Dice / IoU and an
  overall accuracy and Cohen's kappa (e.g. against a `.npy` ground truth).
* `at_write_mask()` writes TIFF/PNG/RDS with a sidecar JSON legend;
  `at_read_mask()` polygonises a mask back into editable ROIs. `at_write_npy()`
  / `at_read_npy()` losslessly interchange integer masks (incl. bitfields) with
  NumPy `.npy`, the format used by external HSI annotation tools.

## Extraction, plots, interchange, and batch

* Tile-wise `at_extract()`, `at_extract_spectrum()`, `at_extract_pixels()`.
* ggplot2 plots `at_plot_image()`, `at_plot_project()`, `at_plot_overlay()`,
  `at_plot_mask()`, `at_plot_spectrum()`, `at_plot_summary()`.
* Round-tripping I/O: `at_write_geojson()`/`at_read_geojson()`,
  `at_write_qupath()`/`at_read_qupath()`, `at_write_rois_csv()`/
  `at_read_rois_csv()`, project/session RDS.
* Whole-session `at_export_all()`, `at_summary_table()`, `at_batch_apply()`,
  `at_batch_check_geometry()`.

## Application

* `at_annotate()` launches a resumable, keyboard-first batch annotation app
  with live mask preview, built on `shiny` and a deep-zoom canvas widget.
