# Source this file after library(annotatR). These are example functions, not
# exported package APIs. See vignettes/reproducible-analysis.Rmd.

prepare_analytical_example <- function(fixture_dir, project_path) {
  # Prepare ONCE. Subsequent runs load this persisted identity and revision.
  # This identifier belongs to the synthetic example, not to an acquired image.
  project <- at_project(
    at_read_image(file.path(fixture_dir, "cube.hdr"), backend = "envi"),
    at_read_geojson(file.path(fixture_dir, "analysis-rois.geojson")),
    name = "Independent analytical example", entry_id = "analytical-image-001",
    annotation_revision = 0L
  )
  at_save_project(project, project_path, overwrite = FALSE)
  invisible(project_path)
}

run_analytical_example <- function(project_path, fixture_dir, output_dir = NULL) {
  if (!is.null(output_dir) && file.exists(output_dir))
    stop("Output directory already exists; choose a new directory.")
  project <- at_load_project(project_path)
  at_validate(project)
  source <- at_inspect_source(project)
  if (!identical(source$status, "available")) stop("Source is not available.")
  if (!identical(normalizePath(source$path),
                 normalizePath(file.path(fixture_dir, "cube.hdr"))))
    stop("This example requires the persisted analytical fixture cube.")
  if (is.null(project$meta$entry_id) || is.null(project$meta$annotation_revision))
    stop("Persist an entry_id and annotation_revision before analysis.")

  # Remove incidental attributes (including creation times) from exported tables.
  plain_table <- function(x) as.data.frame(lapply(x, identity),
                                          stringsAsFactors = FALSE)
  sample_status <- function(x) {
    ifelse(is.nan(x), "NaN", ifelse(is.na(x), "NA",
      ifelse(is.infinite(x), ifelse(x > 0, "+Inf", "-Inf"), "finite")))
  }
  settings_extract <- list(level = 0L, bands = 1:3, layer = NULL, label = NULL,
    nonfinite = "omit", statistics = c("mean", "median", "sd", "min", "max", "sum", "n"),
    max_px = 1000000L, pixel_coordinates = "one-based x column, y row",
    selected_support = "polygon pixel centres; touches=FALSE",
    n = "selected pixels per ROI and band", n_valid = "finite contributors",
    n_invalid = "selected NA, NaN, +Inf or -Inf samples",
    sd = "sample SD, denominator n_valid - 1; singleton is NA",
    empty_or_all_invalid = "All-invalid statistics are NA including sum; empty ROIs yield no summary rows and are counted as excluded; empty image-band rows retain zero counts and NA statistics")
  band_table <- plain_table(at_bands(project$image))
  statistics <- at_extract(project, stat = "all", level = settings_extract$level,
    bands = settings_extract$bands, nonfinite = settings_extract$nonfinite)
  analysis <- attr(statistics, "analysis")
  settings_extract$sample_contract <- analysis$sample_contract
  spectra <- at_extract_spectrum(project, stat = "mean", level = 0L, nonfinite = "omit")
  memberships <- plain_table(at_extract_pixels(project, level = 0L, bands = 1:3,
                                               max_px = settings_extract$max_px))
  memberships$sample_status <- sample_status(memberships$value)
  # Same image and grid: overlapping records refer to the same physical cell.
  # Keep each (x,y,band) once, rather than pooling repeated ROI memberships.
  pixels <- memberships[!duplicated(memberships[c("x", "y", "band")]),
                        c("x", "y", "band", "value", "sample_status")]
  pixels <- pixels[order(pixels$band, pixels$y, pixels$x), ]
  rownames(pixels) <- NULL
  image_statistics <- do.call(rbind, lapply(settings_extract$bands, function(band) {
    values <- pixels$value[pixels$band == band]
    finite <- values[is.finite(values)]
    summarize <- function(f) if (length(finite)) f(finite) else NA_real_
    data.frame(entry_id = project$meta$entry_id, band = band,
      wavelength = band_table$wavelength[band], unit = band_table$unit[band],
      estimand = "unique selected pixels within image", n_selected = length(values),
      n_valid = length(finite), n_invalid = length(values) - length(finite),
      mean = summarize(mean), median = summarize(stats::median), sd = summarize(stats::sd),
      min = summarize(min), max = summarize(max), sum = summarize(sum))
  }))
  mask_settings <- list(type = "multiclass", level = 0L, background = 0L,
    values = list(A = 1L, B = 2L), overlap = "bitor", touches = FALSE, engine = "stars")
  mask <- at_mask(project, type = mask_settings$type, level = mask_settings$level,
    background = mask_settings$background, values = unlist(mask_settings$values),
    overlap = mask_settings$overlap, touches = mask_settings$touches,
    engine = mask_settings$engine)
  mask_matrix <- as.matrix(mask)
  roi_table <- at_rois(project)
  cell_memberships <- unique(memberships[c("roi_id", "x", "y")])
  cells <- unique(cell_memberships[c("x", "y")])
  coverage <- table(paste(cell_memberships$x, cell_memberships$y, sep = ":"))
  counts <- data.frame(entry_id = project$meta$entry_id,
    n_image = 1L, n_roi = nrow(roi_table), n_unique_selected = nrow(cells),
    n_roi_memberships = nrow(cell_memberships), n_overlap = sum(coverage > 1L),
    n_background = length(mask_matrix) - nrow(cells),
    n_excluded_rois = sum(!roi_table$roi_id %in% memberships$roi_id))

  # These separate 3x4 synthetic agreement cases are NOT the 4x5 image above.
  # The independent fixture generator declares matching yx grids. NPY arrays
  # alone cannot prove spatial registration, so record that assertion explicitly.
  read_agreement <- function(file, encoding, codes) at_read_npy(
    file.path(fixture_dir, file), level = 0L, transpose = FALSE,
    legend = data.frame(value = unname(codes), label = names(codes)),
    metadata = list(encoding = encoding, background = 0L))
  categorical_codes <- c(A = 1L, B = 2L, absent = 3L)
  cat_reference <- read_agreement("categorical-reference.npy", "categorical", categorical_codes)
  cat_prediction <- read_agreement("categorical-prediction.npy", "categorical", categorical_codes)
  cat_remapped <- read_agreement("categorical-prediction-remapped.npy", "categorical",
                                c(A = 2L, B = 1L, absent = 3L))
  bit_codes <- c(A = 1L, B = 2L, absent = 4L)
  bit_reference <- read_agreement("bitfield-reference.npy", "bitfield", bit_codes)
  bit_prediction <- read_agreement("bitfield-prediction.npy", "bitfield", bit_codes)
  agreements <- list(
    categorical = at_mask_agreement(cat_reference, cat_prediction,
      alignment = "assert", code_alignment = "strict"),
    categorical_remapped = at_mask_agreement(cat_reference, cat_remapped,
      alignment = "assert", code_alignment = "by-label"),
    bitfield = at_mask_agreement(bit_reference, bit_prediction,
      alignment = "assert", code_alignment = "strict"))
  agreement_table <- do.call(rbind, lapply(names(agreements), function(case)
    data.frame(comparison = case, plain_table(agreements[[case]]))))
  overall_table <- do.call(rbind, lapply(names(agreements), function(case)
    data.frame(comparison = case, attr(agreements[[case]], "overall"))))
  rownames(agreement_table) <- rownames(overall_table) <- NULL

  input_files <- c("cube.hdr", "cube.dat", "analysis-rois.geojson",
    "categorical-reference.npy", "categorical-prediction.npy",
    "categorical-prediction-remapped.npy", "bitfield-reference.npy", "bitfield-prediction.npy")
  hashes <- tools::md5sum(c(file.path(fixture_dir, input_files), project_path))
  names(hashes) <- c(input_files, "persisted_project")
  packages <- c("annotatR", "sf", "stars", "tibble", "dplyr", "jsonlite", "rlang", "cli")
  versions <- setNames(lapply(packages, function(pkg) as.character(utils::packageVersion(pkg))), packages)
  pixel_unit <- at_meta(project$image, "pixel_unit")
  settings <- list(schema = "annotatR-analytical-example-v1",
    annotation = list(entry_id = project$meta$entry_id,
      revision = project$meta$annotation_revision, roi_ids = roi_table$roi_id,
      revision_policy = "caller-managed persisted revision; increment when annotations change"),
    source = list(descriptor = project$image$source_descriptor, inspection = source),
    inputs = list(fixture_directory = normalizePath(fixture_dir),
      project_path = normalizePath(project_path), md5 = as.list(hashes),
      checksum_scope = "Exact input bytes, including ENVI data payload; MD5 integrity, not authentication"),
    calibration = list(level = 0L, pixel_size_xy = at_pixel_size(project$image),
      pixel_unit = pixel_unit, physical_status = "unknown",
      note = "This ENVI fixture declares pixel units only; no physical area or intensity unit is inferred"),
    bands = band_table, extraction = settings_extract, mask = mask_settings,
    mask_metadata = attr(mask, "mask_metadata"), mask_codebook = plain_table(at_mask_legend(mask)),
    backend = list(name = project$image$backend, implementation_package = "annotatR",
      implementation_version = versions$annotatR, plugin_version = "unknown"),
    versions = list(R = as.character(getRversion()), platform = R.version$platform,
      packages = versions, sf_external = as.list(sf::sf_extSoftVersion())),
    sampling_units = list(unique_selected_pixels = nrow(cells),
      selected_roi_memberships = nrow(cell_memberships), roi_count = nrow(roi_table), image_count = 1L),
    estimands = list(pixel_memberships = "one raw ROI-pixel-band record; overlaps repeat",
      unique_pixels = "one raw image-pixel-band record; overlaps deduplicated",
      roi_statistics = "finite-only statistics within each ROI and band; n counts selected support",
      spectra = "per-ROI finite mean at each declared spectral coordinate",
      image_statistics = "finite-only statistics of unique selected pixels per image and band",
      counts = "spatial cells and ROI memberships, counted once across bands; excluded ROIs have no selected cells",
      agreement = "per-class memberships on separate 3x4 reference/prediction grids",
      agreement_overall = "all 12 cells including background; bitfield accuracy is exact-set agreement"),
    agreement = list(alignment = "assert", assertion_basis = "Independent fixture generator declares common yx grids",
      transpose = FALSE, nonfinite = "error", absent_classes = "NA Dice/IoU; excluded from macro means",
      comparisons = lapply(agreements, function(x) attr(x, "comparison"))),
    inference = list(resampling = "none", seed = NULL,
      independent_unit = "not specified; descriptive single-image example",
      note = "Pixels, overlapping ROIs and bands are not independent image replicates; inferential uncertainty requires the study sampling unit"),
    limitations = c(analysis$limitations, "No image preview is generated; mixed nonfinite RGB normalization is not qualified here.",
      "Small synthetic example; no model fitting, clinical inference, native display or vendor-format qualification.",
      "Determinism is for the same persisted inputs and software environment; paths, file signatures and versions are traceable environment-specific provenance."))
  tables <- list(mask = as.data.frame(mask_matrix), mask_codebook = plain_table(at_mask_legend(mask)),
    pixel_memberships = memberships, unique_pixels = pixels,
    roi_statistics = plain_table(statistics), spectra = plain_table(spectra),
    image_statistics = image_statistics, counts = counts,
    agreement = agreement_table, agreement_overall = overall_table)
  result <- list(settings = settings, tables = tables)
  if (!is.null(output_dir)) {
    if (!dir.create(output_dir, recursive = TRUE)) stop("Cannot create output directory.")
    for (name in names(tables)) utils::write.csv(tables[[name]],
      file.path(output_dir, paste0(name, ".csv")), row.names = FALSE, na = "NA")
    # sample_status preserves nonfinite distinctions that CSV NA would collapse.
    jsonlite::write_json(settings, file.path(output_dir, "settings.json"),
      pretty = TRUE, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
  }
  result
}
