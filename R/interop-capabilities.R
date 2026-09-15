# Capability report for the partner contract (qupflowR). A capability is only
# reported as `supported` when its implementation, runtime dependencies and
# qualification evidence all exist; implemented-but-unqualified profiles are
# reported as `planned`, missing runtimes as `unavailable`, each with a reason.

# Contract identifiers. Schema versions are independent of the package version.
.contract <- list(
  consumer = "qupflowR",
  capabilities = "annotatr-capabilities-v1",
  handoff = "annotatr-handoff-v1",
  control = "annotatr-control-v1",
  training = "annotatr-training-v1",
  hsi = "annotatr-hsi-v1",
  version = "1.0",
  integrity_format = "1.0",
  fixture_version = "2026.09.14"
)

# Clients against which the direct-control (I2) and embedded-app (I3) profiles
# have passed their contract tests. Empty until a real qupflowR client run is
# recorded; while empty those profiles stay "planned".
.qualified_clients <- list()

# Limits enforced by the handoff reader, the control service and tile access.
.interop_limits <- function() {
  list(
    control_max_body_bytes = 1048576L,
    control_max_events_buffer = 1000L,
    control_max_events_page = 500L,
    control_max_inline_features = 10000L,
    control_default_ttl_seconds = 900L,
    control_max_ttl_seconds = 86400L,
    handoff_max_json_bytes = 16L * 1048576L,
    handoff_max_files = 100000L,
    mask_preview_max_dim = 1024L,
    region_download_max_pixels = 4194304L,
    max_tile_bytes = .max_tile_bytes()
  )
}

.control_runtime_status <- function() {
  missing <- c("httpuv", "later")[!vapply(c("httpuv", "later"), requireNamespace,
                                          logical(1), quietly = TRUE)]
  list(available = length(missing) == 0L,
       reason = if (length(missing)) paste("missing package(s):", paste(missing, collapse = ", ")) else NA_character_)
}

.app_runtime_status <- function() {
  missing <- .annotate_pkgs[!vapply(.annotate_pkgs, requireNamespace, logical(1), quietly = TRUE)]
  list(available = length(missing) == 0L,
       reason = if (length(missing)) paste("missing package(s):", paste(missing, collapse = ", ")) else NA_character_)
}

# One capability entry.
.cap <- function(status, implemented, available, reason = NA_character_,
                 qualified_with = list(), ...) {
  c(list(status = status, implemented = implemented, available = available,
         reason = reason, qualified_with = qualified_with), list(...))
}

# Per-backend HSI capability rows.
.hsi_backend_caps <- function() {
  cuvis <- .cuvis_status()
  list(
    envi = .cap("supported", TRUE, TRUE, window_read = TRUE,
                tested_versions = list(fixtures = .contract$fixture_version),
                formats = list("hdr+bsq", "hdr+bil", "hdr+bip"),
                dtypes = list("uint8", "int16", "int32", "uint16", "uint32", "float32", "float64"),
                limits = list(no_64bit_integers = TRUE, no_complex = TRUE)),
    tivita = .cap("supported", TRUE, TRUE, window_read = TRUE,
                  tested_versions = list(fixtures = .contract$fixture_version),
                  profiles = list(.TIVITA_DEFAULT_PROFILE),
                  reason = "SpecCube layout requires a declared profile or sidecar; ENVI exports use the envi reader"),
    cuvis = .cap(if (cuvis$available) "planned" else "unavailable", TRUE, cuvis$available,
                 reason = if (cuvis$available) {
                   "SDK present; qualification is a separate local lane (ANNOTATR_CUVIS_FIXTURE)"
                 } else {
                   cuvis$reason
                 },
                 window_read = FALSE,
                 tested_versions = as.list(.cuvis_tested_versions),
                 installed_versions = list(cuvis.r = .pkg_version_or_na("cuvis.r")),
                 fallback = "at_cubert_export_envi() then the envi backend"),
    tiff = .cap(if (requireNamespace("tiff", quietly = TRUE)) "supported" else "unavailable", TRUE,
                requireNamespace("tiff", quietly = TRUE), window_read = FALSE,
                reason = "spectral only with explicit per-band wavelengths; otherwise multichannel"),
    ometiff = .cap(if (requireNamespace("RBioFormats", quietly = TRUE)) "planned" else "unavailable",
                   TRUE, requireNamespace("RBioFormats", quietly = TRUE), window_read = FALSE,
                   reason = if (requireNamespace("RBioFormats", quietly = TRUE)) {
                     "no qualified OME-TIFF fixture run recorded"
                   } else {
                     "package RBioFormats is not installed"
                   })
  )
}

#' Partner interoperability capabilities
#'
#' Report what this annotatR installation can exchange with a partner package
#' such as qupflowR, and how far each capability has been qualified. Profiles
#' follow the partner contract: I0 file interchange, I1 public R API, I2 the
#' local control service (`annotatr-control-v1`) and I3 the embeddable app
#' object from [at_app()]. A profile is `"supported"` only with implementation,
#' runtime dependencies and qualification evidence; implemented profiles that
#' have not passed their tests against a real partner client are `"planned"`;
#' profiles whose optional runtime is missing are `"unavailable"`. Every entry
#' carries a `reason` when it is not supported.
#'
#' @param target One or more of `"package"`, `"hsi"`, `"app"`, `"control"`.
#' @param call The calling environment, for error reporting.
#'
#' @return A list of class `at_capabilities` with `schema`, `schema_version`,
#'   `annotatr_version`, `r_version`, `source_revision`, `consumer`, `profiles`
#'   (I0-I3), `limits`, and the requested sections `package`, `hsi`, `app`,
#'   `control`, plus `digest`: the SHA-256 of the canonical JSON of the report
#'   without `digest` itself.
#' @family interop
#' @seealso [at_interop_manifest()], [at_control_capabilities()]
#' @export
#' @examples
#' caps <- at_interop_capabilities()
#' caps$profiles$I0$status
#' caps$digest
at_interop_capabilities <- function(target = c("package", "hsi", "app", "control"),
                                    call = rlang::caller_env()) {
  if (!is.character(target) || length(target) == 0L ||
      !all(target %in% c("package", "hsi", "app", "control"))) {
    .at_abort("{.arg target} must contain {.val package}, {.val hsi}, {.val app} and/or {.val control}.",
              call = call)
  }
  target <- unique(target)
  app_rt <- .app_runtime_status()
  ctl_rt <- .control_runtime_status()
  qualified <- length(.qualified_clients) > 0L
  profiles <- list(
    I0 = .cap("supported", TRUE, TRUE, description = "file interchange (handoff directory)",
              qualified_with = list(list(tool = "QuPath", version = "0.7.0",
                                         evidence = "QuPath-written and QuPath-read GeoJSON fixtures"))),
    I1 = .cap("supported", TRUE, TRUE, description = "public R API"),
    I2 = .cap(if (!ctl_rt$available) "unavailable" else if (qualified) "supported" else "planned",
              TRUE, ctl_rt$available,
              reason = if (!ctl_rt$available) ctl_rt$reason else if (!qualified) {
                "implemented and tested locally; no qualified qupflowR client run recorded"
              } else NA_character_,
              qualified_with = .qualified_clients,
              description = "loopback control service"),
    I3 = .cap(if (!app_rt$available) "unavailable" else if (qualified) "supported" else "planned",
              TRUE, app_rt$available,
              reason = if (!app_rt$available) app_rt$reason else if (!qualified) {
                "at_app() is implemented and tested locally; no qualified qupflowR embedding recorded"
              } else NA_character_,
              qualified_with = .qualified_clients,
              description = "embeddable shiny.appobj")
  )
  out <- list(
    schema = .contract$capabilities,
    schema_version = .contract$version,
    annotatr_version = .pkg_version(),
    r_version = as.character(getRversion()),
    source_revision = .source_revision(),
    consumer = .contract$consumer,
    profiles = profiles,
    limits = .interop_limits()
  )
  if ("package" %in% target) {
    out$package <- list(
      handoff_schema = .contract$handoff,
      integrity_format = .contract$integrity_format,
      training_schema = .contract$training,
      fixture_version = .contract$fixture_version,
      geometry_formats = list("qupath_geojson", "geojson", "csv", "rds"),
      mask_formats = list(
        list(format = "mask_tiff", dtypes = list("uint8", "uint16")),
        list(format = "mask_png", dtypes = list("uint8")),
        list(format = "mask_npy", dtypes = list("uint8", "int16", "int32")),
        list(format = "rds", dtypes = list("integer", "logical"))
      ),
      mask_types = list("binary", "labelled", "multiclass", "instance"),
      coordinate_convention = .coordinate_convention(),
      hierarchy = "unknown",
      native_roi = "approximated",
      functions = list("at_interop_manifest", "at_export_qupflowr", "at_import_qupflowr",
                       "at_stage_qupflowr", "at_commit_qupflowr", "at_annotation_revision",
                       "at_training_export", "at_training_check", "at_training_import")
    )
  }
  if ("hsi" %in% target) {
    out$hsi <- list(
      schema = .contract$hsi,
      tile_contract = "[y, x, band]",
      value_units = as.list(.value_units),
      conversions = list("raw->reflectance (dark/white calibration)", "reflectance->absorbance"),
      band_operations = as.list(names(.band_ops)),
      backends = .hsi_backend_caps()
    )
  }
  if ("app" %in% target) {
    out$app <- .cap(profiles$I3$status, TRUE, app_rt$available, reason = profiles$I3$reason,
                    builder = "at_app", launcher = "at_annotate",
                    control_modes = list("off", "loopback"))
  }
  if ("control" %in% target) {
    out$control <- c(
      .cap(profiles$I2$status, TRUE, ctl_rt$available, reason = profiles$I2$reason),
      list(protocol = .contract$control, protocol_version = .contract$version,
           endpoints = as.list(.control_endpoint_names()),
           commands = as.list(.control_operations()),
           host = "127.0.0.1", auth = "bearer token (random, TTL-bound)")
    )
  }
  out$digest <- .digest_json(out)
  structure(out, class = "at_capabilities")
}

.coordinate_convention <- function() {
  list(origin = "top_left", x_axis = "right", y_axis = "down", units = "px",
       level_scale = "declared", pixel_centre = "half_integer",
       plane_indexing = "zero_based")
}

#' @export
print.at_capabilities <- function(x, ...) {
  cat(cli::format_inline("{.cls at_capabilities} annotatR {x$annotatr_version} for {x$consumer}"), "\n",
      sep = "")
  for (nm in names(x$profiles)) {
    p <- x$profiles[[nm]]
    reason <- if (is.na(p$reason)) "" else paste0(" - ", p$reason)
    cat(sprintf("  %s %-11s %s%s\n", nm, p$status, p$description %||% "", reason))
  }
  cat("  digest ", x$digest, "\n", sep = "")
  invisible(x)
}
