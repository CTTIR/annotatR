# Changelog

## annotatR 0.2.0

A partner contract for the qupflowR package, a testable app builder with
an optional local control service, hyperspectral metadata and windowed
readers, and deep-learning training datasets. The existing API, S3
classes and files remain compatible; behaviour changes are listed under
*Changes*.

### Partner interoperability (qupflowR)

- [`at_interop_capabilities()`](https://cttir.github.io/annotatR/reference/at_interop_capabilities.md)
  reports the I0-I3 profiles with `status`, `implemented`, `available`
  and `reason`, limits, formats, HSI backends and a capability digest.
  Direct control (I2) and embedding (I3) are reported as `planned` until
  they are qualified against a real qupflowR client.
- [`at_interop_manifest()`](https://cttir.github.io/annotatR/reference/at_interop_manifest.md)
  writes a sanitised `annotatr-handoff-v1` manifest: content-derived
  image ids, dimensions, levels, planes, coordinate convention, band
  tables, HSI value semantics, calibration/transform digests and
  annotation revisions, without local paths.
  [`at_annotation_revision()`](https://cttir.github.io/annotatR/reference/at_annotation_revision.md)
  gives the content revision partners use as `expected_revision`.
- [`at_export_qupflowr()`](https://cttir.github.io/annotatR/reference/at_export_qupflowr.md)
  writes a staged, SHA-256-inventoried handoff directory (QuPath
  GeoJSON, GeoJSON, integer masks with legends, NPY, CSV, RDS, HSI
  manifest). Its digest follows qupflowR’s canonical-JSON bundle digest
  rule.
- [`at_import_qupflowr()`](https://cttir.github.io/annotatR/reference/at_import_qupflowr.md)
  verifies inventory, schema, major version, id joins, labels, mask
  dimensions and legends, and returns namespaced annotatR objects with a
  conversion report.
- [`at_stage_qupflowr()`](https://cttir.github.io/annotatR/reference/at_stage_qupflowr.md)
  and
  [`at_commit_qupflowr()`](https://cttir.github.io/annotatR/reference/at_commit_qupflowr.md)
  apply partner changes as an explicit, revision-checked, idempotent
  diff that never overwrites reviewed or locked annotations.
- JSON Schemas ship under `inst/schema/` and are enforced by a small
  built-in validator. Errors are classified (`at_validation_error`,
  `at_conflict_error`, `at_io_error`, `at_protocol_error`,
  `at_auth_error`, `at_limit_error`, `at_capability_error`) with
  machine-readable `code`s.

### App builder and control service

- [`at_app()`](https://cttir.github.io/annotatR/reference/at_app.md)
  builds the annotation app as a `shiny.appobj` from explicit arguments;
  all app code now lives in `R/`.
  [`at_annotate()`](https://cttir.github.io/annotatR/reference/at_annotate.md)
  is a launcher around it and no longer passes the session through
  [`options()`](https://rdrr.io/r/base/options.html).
  `inst/shiny/annotatR/app.R` remains as a thin compatibility wrapper.
- [`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md),
  [`at_control_stop()`](https://cttir.github.io/annotatR/reference/at_control_stop.md),
  [`at_control_close()`](https://cttir.github.io/annotatR/reference/at_control_close.md),
  [`at_control_connect()`](https://cttir.github.io/annotatR/reference/at_control_connect.md),
  [`at_control_capabilities()`](https://cttir.github.io/annotatR/reference/at_control_capabilities.md),
  [`at_control_state()`](https://cttir.github.io/annotatR/reference/at_control_state.md),
  [`at_control_events()`](https://cttir.github.io/annotatR/reference/at_control_events.md),
  [`at_control_command()`](https://cttir.github.io/annotatR/reference/at_control_command.md)
  and
  [`at_control_request_status()`](https://cttir.github.io/annotatR/reference/at_control_request_status.md)
  implement `annotatr-control-v1`: loopback only, expiring bearer token
  (never in URLs, logs, manifests or RDS), size and path limits,
  monotonic state revision, event cursors with resync, idempotent typed
  commands and response-loss recovery. There is no code-evaluation
  endpoint.
- New app panels: band / pseudo-RGB / band-operation display, cube and
  calibration status, pixel, ROI and layer spectra, raw region download,
  mask overlay on the canvas, staged-patch review with commit/discard,
  and a read-only/unsaved/staged/committed status badge. New `probe` and
  `select` canvas tools and
  [`at_canvas_set_selection()`](https://cttir.github.io/annotatR/reference/at_canvas_set_selection.md).

### Hyperspectral cubes

- [`at_hsi_meta()`](https://cttir.github.io/annotatR/reference/at_hsi_meta.md),
  [`at_read_stats()`](https://cttir.github.io/annotatR/reference/at_read_stats.md),
  [`at_convert_values()`](https://cttir.github.io/annotatR/reference/at_convert_values.md),
  [`at_band_operations()`](https://cttir.github.io/annotatR/reference/at_band_operations.md)
  and
  [`at_band_view()`](https://cttir.github.io/annotatR/reference/at_band_view.md).
- [`at_bands()`](https://cttir.github.io/annotatR/reference/at_bands.md)
  gains `fwhm`, `order` and `wavelength_status` columns; missing or
  duplicated wavelengths are flagged, never interpolated.
- The ENVI reader validates the header and payload length, honours
  `header offset` (a sentinel header byte no longer becomes a pixel),
  supports uint32, keeps FWHM, band names, ignore value, scale factor
  and gain/offset values, and reads windows by seeking instead of
  loading the cube.
- TIVITA SpecCubes are read through
  [`at_tivita_profile()`](https://cttir.github.io/annotatR/reference/at_tivita_profile.md)
  or a `<cube>.tivita.json` sidecar with windowed reads; a file that
  matches no declared profile is refused.
- The Cubert backend was rewritten against the `cuvis.r` 0.1.0 API (the
  previous call did not exist) and records SDK, processing mode and
  calibration provenance;
  [`at_cubert_export_envi()`](https://cttir.github.io/annotatR/reference/at_cubert_export_envi.md)
  writes the portable ENVI fallback. Without the SDK the backend reports
  itself unavailable.
- A TIFF is spectral only with declared `wavelengths`.
- [`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md)
  enforces `options(annotatR.max_tile_bytes)`; app previews read only
  the displayed bands.

### Training datasets

- [`at_training_export()`](https://cttir.github.io/annotatR/reference/at_training_export.md),
  [`at_training_check()`](https://cttir.github.io/annotatR/reference/at_training_check.md)
  and
  [`at_training_import()`](https://cttir.github.io/annotatR/reference/at_training_import.md):
  grouped leakage-free splits, integer tile masks with complete legends,
  band and transform provenance, independent dataset checks, and staged
  prediction import that never overwrites reviewed annotations.

### Changes

- [`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md)
  now writes the QuPath 0.4+ dialect by default (`objectType`,
  `classification.color`, UUID feature ids plus annotatR ids in
  `properties.metadata`), verified with QuPath 0.7.0. Use
  `dialect = "legacy"` for the 0.1 form.
  [`at_read_qupath()`](https://cttir.github.io/annotatR/reference/at_read_qupath.md)
  reads both, including derived classes, measurements, planes, nuclei
  and ellipse flags.
- GeoJSON writers use 17 significant digits so coordinates round-trip
  exactly.
- [`at_roi_circle()`](https://cttir.github.io/annotatR/reference/at_roi_circle.md)
  and
  [`at_roi_ellipse()`](https://cttir.github.io/annotatR/reference/at_roi_ellipse.md)
  record `attributes$shape`.
- Numeric choice arguments such as `bits = 8L` and `connectivity = 4L`
  are accepted; argument validation errors now carry class
  `at_validation_error`.
- Navigating in the app keeps the edited project in its own queue entry,
  and Shift+Enter stores the current project before advancing.
- App export file names are sanitised and unique.
- `R CMD build` excludes a local `inst/shiny/annotatR/hsi-workbench/`
  directory.

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
