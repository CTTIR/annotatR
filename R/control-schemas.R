# The `annotatr-control-v1` protocol surface: endpoints, typed operations,
# request envelope validation and HTTP status mapping. The JSON Schemas under
# inst/schema/annotatr-control-v1/ are authoritative; this file maps them to
# the dispatcher. There is deliberately no endpoint that evaluates R, shell or
# Python code, and no DOM-level control.

# Endpoint table: method, path, operation (NULL for reads) and whether the
# request mutates state.
.control_endpoints <- function() {
  list(
    list(method = "GET", path = "/v1/health", operation = NULL),
    list(method = "GET", path = "/v1/handshake", operation = NULL),
    list(method = "GET", path = "/v1/capabilities", operation = NULL),
    list(method = "GET", path = "/v1/state", operation = NULL),
    list(method = "GET", path = "/v1/events", operation = NULL),
    list(method = "GET", path = "/v1/requests/{request_id}", operation = NULL),
    list(method = "POST", path = "/v1/session/load", operation = "session.load"),
    list(method = "POST", path = "/v1/session/save", operation = "session.save"),
    list(method = "POST", path = "/v1/context/goto", operation = "context.goto"),
    list(method = "POST", path = "/v1/context/view", operation = "context.view"),
    list(method = "POST", path = "/v1/context/selection", operation = "context.selection"),
    list(method = "POST", path = "/v1/annotations/stage", operation = "annotations.stage"),
    list(method = "POST", path = "/v1/annotations/commit", operation = "annotations.commit"),
    list(method = "POST", path = "/v1/mask/preview", operation = "mask.preview"),
    list(method = "POST", path = "/v1/export", operation = "export"),
    list(method = "POST", path = "/v1/training/export", operation = "training.export"),
    list(method = "POST", path = "/v1/close", operation = "close")
  )
}

.control_endpoint_names <- function() {
  vapply(.control_endpoints(), function(e) paste(e$method, e$path), character(1))
}

.control_operations <- function() {
  ops <- vapply(.control_endpoints(), function(e) e$operation %||% NA_character_, character(1))
  ops[!is.na(ops)]
}

# Operation for a POST path, or NULL.
.control_operation_for <- function(path) {
  for (e in .control_endpoints()) {
    if (identical(e$method, "POST") && identical(e$path, path)) {
      return(e$operation)
    }
  }
  NULL
}

# HTTP status for a classified error code.
.control_http_status <- function(code) {
  switch(
    code,
    AUTH_REQUIRED = , TOKEN_INVALID = , TOKEN_EXPIRED = 401L,
    ORIGIN_REJECTED = , HOST_REJECTED = , SCOPE_DENIED = , PATH_OUTSIDE_ROOT = 403L,
    ENDPOINT_NOT_FOUND = , REQUEST_NOT_FOUND = , FILE_MISSING = , IMAGE_NOT_FOUND = ,
    PATCH_NOT_FOUND = 404L,
    METHOD_NOT_ALLOWED = 405L,
    REVISION_CONFLICT = , IDEMPOTENCY_CONFLICT = , DESTINATION_EXISTS = ,
    REVIEWED_CONFLICT = 409L,
    SERVICE_CLOSED = 410L,
    PAYLOAD_TOO_LARGE = , TILE_TOO_LARGE = 413L,
    UNSUPPORTED_MEDIA_TYPE = 415L,
    PROTOCOL_MISMATCH = , INVALID_JSON = , SCHEMA_INVALID = , CONTENT_DIGEST_MISMATCH = ,
    VALIDATION_FAILED = , BAND_OUT_OF_RANGE = , BAND_COUNT = 422L,
    CAPABILITY_UNAVAILABLE = , CALIBRATION_MISSING = 501L,
    INTERNAL_ERROR = 500L,
    422L
  )
}

.control_retryable <- function(code) {
  code %in% c("REVISION_CONFLICT", "INTERNAL_ERROR")
}

#' Control protocol capabilities
#'
#' Describe the `annotatr-control-v1` protocol this annotatR version speaks,
#' without starting anything: endpoints, typed operations, limits, security
#' rules and the digests of the shipped JSON Schemas. A client compares this
#' (or the `/v1/handshake` response) with its own expectations before sending
#' commands.
#'
#' @return A list with `protocol`, `protocol_version`, `annotatr_version`,
#'   `status` (see [at_interop_capabilities()]), `endpoints`, `operations`,
#'   `limits`, `security`, `schemas` (file name -> SHA-256) and `digest`.
#' @family control
#' @seealso [at_control_start()], [at_control_command()]
#' @export
#' @examples
#' cc <- at_control_capabilities()
#' cc$operations
at_control_capabilities <- function() {
  caps <- at_interop_capabilities(target = "control")
  schema_dir <- system.file("schema", .contract$control, package = "annotatR")
  files <- sort(list.files(schema_dir, pattern = "\\.schema\\.json$"))
  schemas <- stats::setNames(
    lapply(files, function(f) .sha256_file(file.path(schema_dir, f))), files
  )
  out <- list(
    protocol = .contract$control,
    protocol_version = .contract$version,
    annotatr_version = .pkg_version(),
    status = caps$control$status,
    implemented = TRUE,
    available = caps$control$available,
    reason = caps$control$reason,
    endpoints = as.list(.control_endpoint_names()),
    operations = as.list(.control_operations()),
    limits = .interop_limits()[grep("^control_", names(.interop_limits()))],
    security = list(
      bind_host = "127.0.0.1",
      auth = "Authorization: Bearer <token>; random 256-bit token, never in URLs, logs, downloads or RDS",
      origin_header = "rejected",
      host_header = "must be 127.0.0.1:<port> or localhost:<port>",
      path_references = "relative to the negotiated root only; no traversal or symlink escape",
      code_execution = "none: no eval, shell, Python or DOM endpoints"
    ),
    mutation_envelope = list("protocol", "protocol_version", "request_id", "expected_revision",
                             "idempotency_key", "operation", "content_sha256", "payload",
                             "extensions"),
    schemas = schemas
  )
  out$digest <- .digest_json(out)
  out
}
