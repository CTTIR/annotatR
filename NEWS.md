# annotatR 0.2.0

A partner contract for the qupflowR package, a testable app builder with an
optional local control service, hyperspectral metadata and windowed readers,
and deep-learning training datasets. The existing API, S3 classes and files
remain compatible; behaviour changes are listed under *Changes*.

## Partner interoperability (qupflowR)

* `at_interop_capabilities()` reports the I0-I3 profiles with `status`,
  `implemented`, `available` and `reason`, limits, formats, HSI backends and a
  capability digest. Direct control (I2) and embedding (I3) are reported as
  `planned` until they are qualified against a real qupflowR client.
* `at_interop_manifest()` writes a sanitised `annotatr-handoff-v1` manifest:
  content-derived image ids, dimensions, levels, planes, coordinate convention,
  band tables, HSI value semantics, calibration/transform digests and annotation
  revisions, without local paths. `at_annotation_revision()` gives the content
  revision partners use as `expected_revision`.
* `at_export_qupflowr()` writes a staged, SHA-256-inventoried handoff directory
  (QuPath GeoJSON, GeoJSON, integer masks with legends, NPY, CSV, RDS, HSI
  manifest). Its digest follows qupflowR's canonical-JSON bundle digest rule.
* `at_import_qupflowr()` verifies inventory, schema, major version, id joins,
  labels, mask dimensions and legends, and returns namespaced annotatR objects
  with a conversion report.
* `at_stage_qupflowr()` and `at_commit_qupflowr()` apply partner changes as an
  explicit, revision-checked, idempotent diff that never overwrites reviewed or
  locked annotations.
* JSON Schemas ship under `inst/schema/` and are enforced by a small built-in
  validator. Errors are classified (`at_validation_error`,
  `at_conflict_error`, `at_io_error`, `at_protocol_error`, `at_auth_error`,
  `at_limit_error`, `at_capability_error`) with machine-readable `code`s.

## App builder and control service

* `at_app()` builds the annotation app as a `shiny.appobj` from explicit
  arguments; all app code now lives in `R/`. `at_annotate()` is a launcher
  around it and no longer passes the session through `options()`.
  `inst/shiny/annotatR/app.R` remains as a thin compatibility wrapper.
* `at_control_start()`, `at_control_stop()`, `at_control_close()`,
  `at_control_connect()`, `at_control_capabilities()`, `at_control_state()`,
  `at_control_events()`, `at_control_command()` and
  `at_control_request_status()` implement `annotatr-control-v1`: loopback only,
  expiring bearer token (never in URLs, logs, manifests or RDS), size and path
  limits, monotonic state revision, event cursors with resync, idempotent
  typed commands and response-loss recovery. There is no code-evaluation
  endpoint.
* New app panels: band / pseudo-RGB / band-operation display, cube and
  calibration status, pixel, ROI and layer spectra, raw region download, mask
  overlay on the canvas, staged-patch review with commit/discard, and a
  read-only/unsaved/staged/committed status badge. New `probe` and `select`
  canvas tools and `at_canvas_set_selection()`.

## Hyperspectral cubes

* `at_hsi_meta()`, `at_read_stats()`, `at_convert_values()`,
  `at_band_operations()` and `at_band_view()`.
* `at_bands()` gains `fwhm`, `order` and `wavelength_status` columns; missing
  or duplicated wavelengths are flagged, never interpolated.
* The ENVI reader validates the header and payload length, honours
  `header offset` (a sentinel header byte no longer becomes a pixel), supports
  uint32, keeps FWHM, band names, ignore value, scale factor and gain/offset
  values, and reads windows by seeking instead of loading the cube.
* TIVITA SpecCubes are read through `at_tivita_profile()` or a
  `<cube>.tivita.json` sidecar with windowed reads; a file that matches no
  declared profile is refused.
* The Cubert backend was rewritten against the `cuvis.r` 0.1.0 API (the
  previous call did not exist) and records SDK, processing mode and
  calibration provenance; `at_cubert_export_envi()` writes the portable ENVI
  fallback. Without the SDK the backend reports itself unavailable.
* A TIFF is spectral only with declared `wavelengths`.
* `at_tile()` enforces `options(annotatR.max_tile_bytes)`; app previews read
  only the displayed bands.

## Training datasets

* `at_training_export()`, `at_training_check()` and `at_training_import()`:
  grouped leakage-free splits, integer tile masks with complete legends, band
  and transform provenance, independent dataset checks, and staged prediction
  import that never overwrites reviewed annotations.

## Changes

* `at_write_qupath()` now writes the QuPath 0.4+ dialect by default
  (`objectType`, `classification.color`, UUID feature ids plus annotatR ids in
  `properties.metadata`), verified with QuPath 0.7.0. Use
  `dialect = "legacy"` for the 0.1 form. `at_read_qupath()` reads both,
  including derived classes, measurements, planes, nuclei and ellipse flags.
* GeoJSON writers use 17 significant digits so coordinates round-trip exactly.
* `at_roi_circle()` and `at_roi_ellipse()` record `attributes$shape`.
* Numeric choice arguments such as `bits = 8L` and `connectivity = 4L` are
  accepted; argument validation errors now carry class `at_validation_error`.
* Navigating in the app keeps the edited project in its own queue entry, and
  Shift+Enter stores the current project before advancing.
* App export file names are sanitised and unique.
* `R CMD build` excludes a local `inst/shiny/annotatR/hsi-workbench/` directory.

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
