# Request dispatcher and typed command handlers of `annotatr-control-v1`. The
# same dispatcher serves the loopback HTTP server and in-process handles, so the
# security, validation, revision and idempotency rules are identical on both
# paths. Handlers only call public annotatR functions on the hub's session.

# A classified control failure carried to the response builder.
.control_fail <- function(code, message, details = list(), class = "validation") {
  .at_abort(message, class = class, code = code, details = details)
}

.control_response <- function(hub, status, request_id, data = NULL, error = NULL,
                              warnings = list(), extra = list()) {
  body <- c(list(
    protocol = .contract$control,
    protocol_version = .contract$version,
    request_id = request_id,
    instance_id = hub$instance_id,
    state_revision = as.character(hub$revision),
    event_cursor = .hub_event_cursor(hub)
  ), extra)
  if (!is.null(error)) {
    body$error <- error
  } else {
    body$data <- data %||% .json_object()
  }
  body$warnings <- warnings
  list(status = as.integer(status), body = body)
}

.control_error_body <- function(cnd) {
  code <- .condition_code(cnd)
  msg <- cli::ansi_strip(conditionMessage(cnd))
  details <- cnd$details %||% list()
  list(code = code, message_key = tolower(code), message = msg,
       details = if (length(details)) .json_safe(details) else .json_object(),
       retryable = .control_retryable(code))
}

.header <- function(headers, name) {
  v <- headers[[tolower(name)]]
  if (is.null(v) || length(v) == 0L || !nzchar(v[1])) NULL else as.character(v[1])
}

.constant_time_equal <- function(a, b) {
  identical(.sha256_bytes(paste0("annotatR-token:", a)), .sha256_bytes(paste0("annotatR-token:", b)))
}

# Security gate shared by every request: Host, Origin, bearer token, TTL.
.control_gate <- function(hub, headers, transport = "http") {
  host <- .header(headers, "host")
  allowed <- c(paste0("127.0.0.1:", hub$port), paste0("localhost:", hub$port))
  if (!identical(transport, "in_process") && (is.null(host) || !host %in% allowed)) {
    .control_fail("HOST_REJECTED", "The Host header is not the loopback control address.",
                  class = "auth")
  }
  if (!is.null(.header(headers, "origin"))) {
    .control_fail("ORIGIN_REJECTED", "Browser-origin requests are not accepted.", class = "auth")
  }
  auth <- .header(headers, "authorization")
  if (is.null(auth) || !grepl("^Bearer [0-9a-f]{64}$", auth)) {
    .control_fail("AUTH_REQUIRED", "A bearer token is required.", class = "auth")
  }
  token <- .control_tokens[[hub$instance_id]]
  if (is.null(token) || !.constant_time_equal(sub("^Bearer ", "", auth), token)) {
    .control_fail("TOKEN_INVALID", "The bearer token is not valid for this instance.", class = "auth")
  }
  if (Sys.time() > hub$expires_at) {
    hub$status <- "expired"
    .control_fail("TOKEN_EXPIRED", "The control session has expired.", class = "auth")
  }
  if (!identical(hub$status, "running")) {
    .control_fail("SERVICE_CLOSED", "The control service is closed.", class = "protocol")
  }
  invisible(TRUE)
}

.parse_query <- function(query) {
  query <- sub("^\\?", "", query %||% "")
  if (!nzchar(query)) {
    return(list())
  }
  parts <- strsplit(strsplit(query, "&", fixed = TRUE)[[1]], "=", fixed = TRUE)
  out <- lapply(parts, function(p) utils::URLdecode(if (length(p) > 1L) p[2] else ""))
  names(out) <- vapply(parts, function(p) utils::URLdecode(p[1]), character(1))
  out
}

# Dispatch one request (HTTP or in-process) and return list(status, body).
.control_handle_request <- function(hub, method, path, query = "", headers = list(), body = raw(),
                                    transport = "http") {
  names(headers) <- tolower(names(headers))
  request_id <- .header(headers, "x-request-id") %||% paste0("request-", .uuid())
  result <- tryCatch({
    .control_gate(hub, headers, transport)
    if (identical(method, "GET")) {
      .control_get(hub, path, .parse_query(query), request_id)
    } else if (identical(method, "POST")) {
      .control_post(hub, path, headers, body, request_id)
    } else {
      .control_fail("METHOD_NOT_ALLOWED", "Only GET and POST are supported.")
    }
  }, error = function(cnd) {
    code <- .condition_code(cnd)
    .control_response(hub, .control_http_status(code), request_id, error = .control_error_body(cnd))
  })
  result
}

.control_get <- function(hub, path, query, request_id) {
  ok <- function(data) .control_response(hub, 200L, request_id, data = data)
  if (identical(path, "/v1/health")) return(ok(.hub_health(hub)))
  if (identical(path, "/v1/handshake")) return(ok(.hub_handshake(hub)))
  if (identical(path, "/v1/capabilities")) return(ok(at_control_capabilities()))
  if (identical(path, "/v1/state")) return(ok(.hub_state(hub)))
  if (identical(path, "/v1/events")) {
    return(ok(.hub_events_after(hub, query$after, query$limit %||% 100L)))
  }
  if (grepl("^/v1/requests/[A-Za-z0-9._:-]{1,128}$", path)) {
    id <- sub("^/v1/requests/", "", path)
    rec <- hub$requests[[id]]
    if (is.null(rec)) {
      .control_fail("REQUEST_NOT_FOUND", "No request with this id is known to this instance.")
    }
    return(ok(rec))
  }
  if (!is.null(.control_operation_for(path))) {
    .control_fail("METHOD_NOT_ALLOWED", "This endpoint only accepts POST.")
  }
  .control_fail("ENDPOINT_NOT_FOUND", "Unknown endpoint.")
}

.control_post <- function(hub, path, headers, body, request_id) {
  operation <- .control_operation_for(path)
  if (is.null(operation)) {
    if (grepl("^/v1/(health|handshake|capabilities|state|events|requests)", path)) {
      .control_fail("METHOD_NOT_ALLOWED", "This endpoint only accepts GET.")
    }
    .control_fail("ENDPOINT_NOT_FOUND", "Unknown endpoint.")
  }
  ctype <- .header(headers, "content-type") %||% ""
  if (!grepl("^application/json", ctype)) {
    .control_fail("UNSUPPORTED_MEDIA_TYPE", "Requests must be application/json.")
  }
  if (length(body) > hub$max_body_bytes) {
    .control_fail("PAYLOAD_TOO_LARGE", "The request body exceeds the size limit.",
                  details = list(limit_bytes = hub$max_body_bytes), class = "limit")
  }
  txt <- rawToChar(body)
  Encoding(txt) <- "UTF-8"
  env <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(env) || is.null(names(env))) {
    .control_fail("INVALID_JSON", "The request body is not a JSON object.")
  }
  if (!identical(env$protocol, .contract$control)) {
    .control_fail("PROTOCOL_MISMATCH", "Unknown protocol.", class = "protocol")
  }
  .check_major_version(env$protocol_version, 1L, "control protocol")
  .schema_assert(env, .contract$control, "command", what = "command")
  if (!identical(env$operation, operation)) {
    .control_fail("VALIDATION_FAILED", "The operation does not match the endpoint.",
                  details = list(endpoint_operation = operation))
  }
  request_id <- env$request_id
  payload <- env$payload %||% .json_object()
  digest <- .digest_json(payload)
  if (!identical(env$content_sha256, digest)) {
    .control_fail("CONTENT_DIGEST_MISMATCH", "content_sha256 does not match the canonical payload.")
  }
  prior_req <- hub$requests[[request_id]]
  prior_key <- hub$idempotency[[env$idempotency_key]]
  if (!is.null(prior_key)) {
    if (!identical(prior_key$content_sha256, digest) || !identical(prior_key$operation, operation)) {
      .control_fail("IDEMPOTENCY_CONFLICT", "This idempotency key was used for a different request.",
                    class = "conflict")
    }
    rec <- hub$requests[[prior_key$request_id]]
    if (!is.null(rec)) {
      resp <- rec$response
      resp$body$replayed <- TRUE
      return(resp)
    }
  }
  if (!is.null(prior_req) && !identical(prior_req$content_sha256, digest)) {
    .control_fail("IDEMPOTENCY_CONFLICT", "This request id was used for a different request.",
                  class = "conflict")
  }
  mutating <- operation %in% c("session.load", "context.goto", "context.view",
                               "context.selection", "annotations.stage", "annotations.commit",
                               "session.save", "close")
  if (mutating && !identical(as.character(env$expected_revision), as.character(hub$revision))) {
    .control_fail("REVISION_CONFLICT", "The state revision changed; re-read the state.",
                  details = list(expected = env$expected_revision,
                                 actual = as.character(hub$revision)),
                  class = "conflict")
  }
  record <- list(request_id = request_id, operation = operation,
                 idempotency_key = env$idempotency_key, content_sha256 = digest,
                 received_at = .utc_stamp(), extensions = env$extensions %||% .json_object())
  resp <- tryCatch({
    data <- .control_execute(hub, operation, payload, env)
    .control_response(hub, 200L, request_id, data = data)
  }, error = function(cnd) {
    code <- .condition_code(cnd)
    .control_response(hub, .control_http_status(code), request_id, error = .control_error_body(cnd))
  })
  record$status <- if (is.null(resp$body$error)) "completed" else "failed"
  record$http_status <- resp$status
  record$completed_at <- .utc_stamp()
  record$response <- resp
  .hub_record_request(hub, record)
  if (is.null(resp$body$error)) {
    assign(env$idempotency_key, list(content_sha256 = digest, operation = operation,
                                     request_id = request_id), envir = hub$idempotency)
  }
  resp
}

.require_writable <- function(hub) {
  if (isTRUE(hub$read_only)) {
    .control_fail("SCOPE_DENIED", "This control session is read-only.", class = "auth")
  }
}

.payload_int <- function(x, name, min = 0L) {
  if (is.null(x) || !is.numeric(x) || length(x) != 1L || is.na(x) || x != round(x) || x < min) {
    .control_fail("VALIDATION_FAILED", sprintf("'%s' must be an integer >= %d.", name, min))
  }
  as.integer(x)
}

.control_execute <- function(hub, operation, payload, env) {
  origin <- list(kind = "control", request_id = env$request_id)
  switch(
    operation,
    "session.load" = .cmd_session_load(hub, payload, origin),
    "session.save" = .cmd_session_save(hub, payload, origin),
    "context.goto" = .cmd_goto(hub, payload, origin),
    "context.view" = .cmd_view(hub, payload, origin),
    "context.selection" = .cmd_selection(hub, payload, origin),
    "annotations.stage" = .cmd_stage(hub, payload, origin),
    "annotations.commit" = .cmd_commit(hub, payload, env, origin),
    "mask.preview" = .cmd_mask_preview(hub, payload),
    "export" = .cmd_export(hub, payload, origin),
    "training.export" = .cmd_training_export(hub, payload, origin),
    "close" = .cmd_close(hub, origin),
    .control_fail("ENDPOINT_NOT_FOUND", "Unknown operation.")
  )
}

# ---- Handlers -------------------------------------------------------------------

.cmd_session_load <- function(hub, payload, origin) {
  .require_writable(hub)
  imgs <- payload$images
  if (!is.list(imgs) || length(imgs) == 0L) {
    .control_fail("VALIDATION_FAILED", "'images' must list image paths relative to the root.")
  }
  paths <- vapply(imgs, function(p) .resolve_under_root(hub$root, as.character(p)), character(1))
  labels <- as.character(unlist(payload$labels %||% list()))
  sess <- at_session(paths, labels = labels, out_dir = hub$session$out_dir)
  if (!is.null(payload$handoff)) {
    dir <- .resolve_under_root(hub$root, as.character(payload$handoff))
    rep <- at_import_qupflowr(dir)
    layers <- rep$objects$layers
    if (length(layers) && all(vapply(layers, inherits, logical(1), "annot_layer"))) {
      p <- .materialize_project(sess, 1L)
      for (L in layers) {
        if (is.null(p$layers[[L$name]])) p <- at_add_layer(p, at_layer(L$name, labels = L$labels, style = L$style))
        for (r in L$rois) p <- at_add_roi(p, L$name, r)
      }
      sess$projects[[1]] <- p
    }
  }
  hub$session <- sess
  hub$view$bounds <- NULL
  hub$view$band_group <- NULL
  hub$selection <- character()
  hub$staged <- NULL
  hub$annotation_status <- "clean"
  .hub_bump(hub, "session.loaded", list(n_images = length(paths)), origin)
  list(n_images = length(paths), queue_index = 1L,
       annotation_revision = at_annotation_revision(sess))
}

.cmd_session_save <- function(hub, payload, origin) {
  .require_writable(hub)
  sess <- hub$session
  sess$projects <- lapply(sess$projects, .lite_project)
  at_save_session(sess, overwrite = TRUE)
  hub$annotation_status <- if (identical(hub$annotation_status, "committed")) "committed" else "clean"
  .hub_bump(hub, "session.saved", list(annotation_revision = at_annotation_revision(hub$session)),
            origin)
  list(saved = TRUE, annotation_revision = at_annotation_revision(hub$session))
}

.cmd_goto <- function(hub, payload, origin) {
  n <- nrow(hub$session$manifest)
  target <- NULL
  if (!is.null(payload$queue_index)) {
    target <- .payload_int(payload$queue_index, "queue_index", 1L)
  } else if (!is.null(payload$entry_id)) {
    target <- suppressWarnings(as.integer(sub("^entry-", "", payload$entry_id)))
  } else if (!is.null(payload$image_id)) {
    ids <- vapply(seq_len(n), function(i) .hub_image_id(hub, i), character(1))
    target <- match(payload$image_id, ids)
  }
  if (is.null(target) || is.na(target) || target < 1L || target > n) {
    .control_fail("IMAGE_NOT_FOUND", "No queue entry matches the request.")
  }
  hub$session <- at_goto(hub$session, target)
  hub$selection <- character()
  hub$staged <- NULL
  hub$view$bounds <- NULL
  proj <- .hub_project(hub)
  .hub_bump(hub, "image.changed", list(queue_index = target,
                                       entry_id = sprintf("entry-%04d", target)), origin)
  list(queue_index = target, entry_id = sprintf("entry-%04d", target),
       image_id = .hub_image_id(hub, target), annotation_revision = at_annotation_revision(proj))
}

.cmd_view <- function(hub, payload, origin) {
  proj <- .hub_project(hub)
  img <- proj$image
  view <- hub$view
  if (!is.null(payload$level)) {
    lvl <- .payload_int(payload$level, "level", 0L)
    if (lvl > img$n_levels - 1L) {
      .control_fail("VALIDATION_FAILED", "The level does not exist for this image.")
    }
    view$level <- lvl
  }
  if (!is.null(payload$bounds)) {
    b <- suppressWarnings(as.numeric(unlist(payload$bounds)))
    d <- img$level_dims[[1]]
    if (length(b) != 4L || anyNA(b) || b[1] >= b[3] || b[2] >= b[4] ||
        b[1] < 0 || b[2] < 0 || b[3] > d[1] || b[4] > d[2]) {
      .control_fail("VALIDATION_FAILED", "bounds must be [xmin, ymin, xmax, ymax] inside the image (level-0 px).")
    }
    view$bounds <- as.list(b)
  }
  if (!is.null(payload$band_group)) {
    bg <- payload$band_group
    spec <- tryCatch(
      .check_band_view(img, bg$operation %||% "rgb",
                       if (is.null(bg$bands)) NULL else as.integer(unlist(bg$bands)),
                       bg$params %||% list()),
      error = function(e) {
        .control_fail(.condition_code(e) %||% "VALIDATION_FAILED", cli::ansi_strip(conditionMessage(e)))
      }
    )
    view$band_group <- list(operation = spec$operation, bands = as.list(spec$bands),
                            params = if (length(spec$params)) spec$params else .json_object())
  }
  if (!is.null(payload$tool)) {
    tool <- as.character(payload$tool)
    if (!tool %in% .canvas_tool_names) {
      .control_fail("VALIDATION_FAILED", "Unknown tool.")
    }
    if (hub$read_only && !tool %in% c("pan", "probe", "select")) {
      .control_fail("SCOPE_DENIED", "Drawing tools are disabled in a read-only session.", class = "auth")
    }
    view$tool <- tool
  }
  if (!is.null(payload$overlay)) {
    ov <- payload$overlay
    mt <- ov$mask_type %||% "labelled"
    if (!mt %in% c("binary", "labelled", "multiclass")) {
      .control_fail("VALIDATION_FAILED", "Unknown overlay mask_type.")
    }
    alpha <- as.numeric(ov$alpha %||% 0.5)
    if (length(alpha) != 1L || is.na(alpha) || alpha < 0 || alpha > 1) {
      .control_fail("VALIDATION_FAILED", "overlay alpha must be in [0, 1].")
    }
    view$overlay <- list(show = isTRUE(ov$show), mask_type = mt, alpha = alpha)
  }
  hub$view <- view
  .hub_bump(hub, "view.changed", list(view = view), origin)
  list(view = view)
}

.cmd_selection <- function(hub, payload, origin) {
  ids <- as.character(unlist(payload$roi_ids %||% list()))
  proj <- .hub_project(hub)
  known <- .all_roi_ids(proj)
  missing <- setdiff(ids, known)
  if (length(missing)) {
    .control_fail("VALIDATION_FAILED", "Unknown ROI ids in the selection.",
                  details = list(missing = as.list(utils::head(missing, 20L))))
  }
  hub$selection <- ids
  .hub_bump(hub, "selection.changed", list(roi_ids = as.list(ids)), origin)
  list(roi_ids = as.list(ids))
}

.cmd_stage <- function(hub, payload, origin) {
  .require_writable(hub)
  proj <- .hub_project(hub)
  report <- if (!is.null(payload$payload_ref)) {
    ref <- .resolve_under_root(hub$root, as.character(payload$payload_ref))
    if (!is.null(payload$payload_sha256) && !dir.exists(ref) &&
        !identical(.sha256_file(ref), payload$payload_sha256)) {
      .control_fail("CONTENT_DIGEST_MISMATCH", "payload_ref does not match payload_sha256.")
    }
    at_import_qupflowr(ref)
  } else if (!is.null(payload$features)) {
    feats <- payload$features
    if (length(feats) > .interop_limits()$control_max_inline_features) {
      .control_fail("PAYLOAD_TOO_LARGE", "Too many inline features.", class = "limit")
    }
    tmp <- tempfile(fileext = ".geojson")
    on.exit(unlink(tmp), add = TRUE)
    jsonlite::write_json(list(type = "FeatureCollection", features = feats), tmp,
                         auto_unbox = TRUE, digits = I(17), null = "null")
    at_import_qupflowr(tmp, format = "qupath_geojson")
  } else {
    .control_fail("VALIDATION_FAILED", "Provide 'payload_ref' or inline 'features'.")
  }
  patch <- at_stage_qupflowr(proj, report, expected_revision = payload$expected_annotation_revision,
                             delete_missing = isTRUE(payload$delete_missing))
  hub$staged <- patch
  hub$annotation_status <- "staged"
  .hub_bump(hub, "annotations.staged", list(patch_id = patch$patch_id, summary = patch$summary),
            origin)
  ops <- patch$operations
  list(patch_id = patch$patch_id, summary = patch$summary,
       base_revision = patch$base_revision, proposed_revision = patch$proposed_revision,
       operations = lapply(seq_len(min(nrow(ops), 2000L)), function(i) as.list(ops[i, ])),
       operations_truncated = nrow(ops) > 2000L)
}

.cmd_commit <- function(hub, payload, env, origin) {
  .require_writable(hub)
  st <- hub$staged
  if (is.null(st) || !identical(payload$patch_id, st$patch_id)) {
    .control_fail("PATCH_NOT_FOUND", "No staged patch with this id.")
  }
  proj <- .hub_project(hub)
  if (!identical(at_annotation_revision(proj), st$base_revision)) {
    hub$staged <- NULL
    .control_fail("REVISION_CONFLICT", "The image annotations changed since staging; stage again.",
                  class = "conflict")
  }
  rc <- at_commit_qupflowr(st, idempotency_key = paste0("control:", env$idempotency_key))
  i <- hub$session$cursor
  hub$session$projects[[i]] <- rc$project
  hub$session$manifest$n_rois[i] <- nrow(at_rois(rc$project))
  sess <- hub$session
  sess$projects <- lapply(sess$projects, .lite_project)
  at_save_session(sess, overwrite = TRUE)
  hub$staged <- NULL
  hub$annotation_status <- "committed"
  hub$last_commit <- list(patch_id = rc$patch_id, new_revision = rc$new_revision,
                          previous_revision = rc$previous_revision,
                          committed_at = rc$committed_at, applied = nrow(rc$applied),
                          conflicts = nrow(rc$conflicts))
  .hub_bump(hub, "annotations.committed", hub$last_commit, origin)
  c(hub$last_commit, list(session_saved = TRUE))
}

.cmd_mask_preview <- function(hub, payload) {
  proj <- .hub_project(hub)
  mt <- payload$mask_type %||% "labelled"
  if (!mt %in% c("binary", "labelled", "multiclass")) {
    .control_fail("VALIDATION_FAILED", "Unknown mask_type.")
  }
  overlap <- payload$overlap %||% "last"
  if (!overlap %in% c("last", "first", "max", "min", "bitor")) {
    .control_fail("VALIDATION_FAILED", "Unknown overlap policy.")
  }
  level <- .payload_int(payload$level %||% 0L, "level", 0L)
  if (level > proj$image$n_levels - 1L) {
    .control_fail("VALIDATION_FAILED", "The level does not exist for this image.")
  }
  max_dim <- min(.payload_int(payload$max_dim %||% 256L, "max_dim", 1L),
                 .interop_limits()$mask_preview_max_dim)
  m <- at_mask(proj, type = mt, level = level, overlap = overlap)
  pv <- at_mask_preview(m, max_dim = max_dim)
  rec <- .mask_record(m)
  out <- list(mask_type = mt, level = level, width = rec$width, height = rec$height,
              preview_width = ncol(as.matrix(pv)), preview_height = nrow(as.matrix(pv)),
              legend = rec$legend, legend_sha256 = rec$legend_sha256,
              mask_sha256 = .sha256_bytes(writeBin(as.integer(as.matrix(m)), raw(), size = 4L, endian = "little")))
  if (isTRUE(payload$include_png)) {
    out$png_base64 <- sub("^data:image/png;base64,", "", .mask_data_uri(pv, max_dim = max_dim) %||% "")
  }
  .hub_event(hub, "mask.previewed", list(mask_type = mt, level = level))
  out
}

.control_output_dir <- function(hub, sub, name) {
  if (!.is_string(name) || !grepl("^[A-Za-z0-9._-]{1,64}$", name) || name %in% c(".", "..")) {
    .control_fail("VALIDATION_FAILED", "'destination' must be a simple name of letters, digits, '.', '_' or '-'.")
  }
  base <- file.path(hub$root, sub)
  dir.create(base, recursive = TRUE, showWarnings = FALSE)
  file.path(normalizePath(base, winslash = "/"), name)
}

.cmd_export <- function(hub, payload, origin) {
  dest <- .control_output_dir(hub, "exports", payload$destination)
  formats <- as.character(unlist(payload$formats %||% list("qupath_geojson", "mask_tiff", "manifest")))
  scope <- payload$scope %||% "current"
  if (!scope %in% c("current", "all", "complete")) {
    .control_fail("VALIDATION_FAILED", "scope must be current, all or complete.")
  }
  x <- if (identical(scope, "current")) .hub_project(hub) else hub$session
  if (!identical(scope, "current")) {
    hub$session$projects[[hub$session$cursor]] <- .hub_project(hub)
    x <- hub$session
  }
  rc <- at_export_qupflowr(x, dest, formats = formats, overwrite = isTRUE(payload$overwrite),
                           scope = if (identical(scope, "current")) "all" else scope)
  out <- list(destination = paste0("exports/", basename(dest)), handoff_digest = rc$handoff_digest,
              files = lapply(seq_len(nrow(rc$files)), function(i) as.list(rc$files[i, ])),
              skipped = as.list(rc$skipped))
  .hub_event(hub, "export.completed", list(destination = out$destination,
                                           handoff_digest = rc$handoff_digest), origin)
  out
}

.cmd_training_export <- function(hub, payload, origin) {
  dest <- .control_output_dir(hub, "training", payload$destination)
  hub$session$projects[[hub$session$cursor]] <- .hub_project(hub)
  split <- payload$split
  rc <- at_training_export(
    hub$session, dest,
    split = if (is.null(split)) NULL else lapply(split, function(v) if (is.list(v)) unlist(v) else v),
    tile_size = .payload_int(payload$tile_size %||% 256L, "tile_size", 8L),
    overlap = .payload_int(payload$overlap %||% 0L, "overlap", 0L),
    level = .payload_int(payload$level %||% 0L, "level", 0L),
    mask_type = payload$mask_type %||% "labelled",
    bands = if (is.null(payload$bands)) NULL else as.integer(unlist(payload$bands)),
    seed = .payload_int(payload$seed %||% 1L, "seed", 0L),
    overwrite = isTRUE(payload$overwrite)
  )
  out <- list(destination = paste0("training/", basename(dest)), dataset_digest = rc$dataset_digest,
              counts = rc$manifest$counts, checks = lapply(seq_len(nrow(rc$checks)), function(i) as.list(rc$checks[i, ])))
  .hub_event(hub, "training.exported", list(destination = out$destination,
                                            dataset_digest = rc$dataset_digest), origin)
  out
}

.cmd_close <- function(hub, origin) {
  .hub_bump(hub, "connection.closing", list(reason = "close requested"), origin)
  hub$status <- "closing"
  if (!is.null(hub$server) && requireNamespace("later", quietly = TRUE)) {
    later::later(function() .control_shutdown(hub, "close requested"), delay = 0.2)
  } else {
    .control_shutdown(hub, "close requested")
  }
  list(closing = TRUE, instance_id = hub$instance_id)
}
