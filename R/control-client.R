# Reference client for `annotatr-control-v1`. Local handles call the shared
# dispatcher in-process; remote handles speak HTTP to 127.0.0.1 with the token
# read from a token file. Error responses become classified R conditions.

.control_remote_tokens <- new.env(parent = emptyenv())

#' Connect to a running control service
#'
#' Build a remote handle for a control service started in another R process,
#' from its lifecycle manifest and token file. The handshake is checked before
#' the handle is returned: protocol, major version and instance id must match
#' the manifest.
#'
#' @param manifest Path of the `annotatr-control-<instance_id>.json` manifest.
#' @param token_file Path of the token file passed to [at_control_start()].
#' @param call The calling environment, for error reporting.
#' @return An `at_control_handle` of kind `"remote"`.
#' @family control
#' @export
at_control_connect <- function(manifest, token_file, call = rlang::caller_env()) {
  .check_file(manifest, call = call)
  .check_file(token_file, call = call)
  if (!requireNamespace("curl", quietly = TRUE)) {
    .at_abort("Connecting to a remote control service needs the {.pkg curl} package.",
              class = "capability", code = "CAPABILITY_UNAVAILABLE", call = call)
  }
  doc <- .read_json_doc(manifest, max_bytes = 1024^2, call = call)
  if (!identical(doc$protocol, .contract$control)) {
    .at_abort("The manifest is not an {.val {(.contract$control)}} service.", class = "protocol",
              code = "PROTOCOL_MISMATCH", call = call)
  }
  .check_major_version(doc$protocol_version, 1L, "control protocol", call = call)
  if (!identical(doc$state, "running")) {
    .at_abort("The control service is {.val {doc$state}}.", class = "protocol",
              code = "SERVICE_CLOSED", call = call)
  }
  if (!identical(doc$host, "127.0.0.1")) {
    .at_abort("Refusing a non-loopback control host.", class = "auth", code = "HOST_REJECTED",
              call = call)
  }
  token <- trimws(readLines(token_file, n = 1L, warn = FALSE))
  if (!grepl("^[0-9a-f]{64}$", token)) {
    .at_abort("The token file does not contain a valid token.", class = "auth",
              code = "TOKEN_INVALID", call = call)
  }
  handle <- structure(
    list(kind = "remote", instance_id = doc$instance_id, session_id = doc$session_id,
         host = doc$host, port = as.integer(doc$port), pid = as.integer(doc$pid),
         manifest = normalizePath(manifest, winslash = "/"), expires_at = doc$expires_at,
         serving = TRUE),
    class = "at_control_handle"
  )
  key <- paste0(handle$instance_id, "@", handle$port)
  assign(key, token, envir = .control_remote_tokens)
  hs <- .control_call(handle, "GET", "/v1/handshake", call = call)
  if (!identical(hs$instance_id, doc$instance_id)) {
    .at_abort("The service answering on port {handle$port} is a different instance.",
              class = "auth", code = "INSTANCE_MISMATCH", call = call)
  }
  handle
}

# Raise the error carried by a control response as a classified condition.
.control_raise <- function(body, status, call) {
  err <- body$error
  code <- err$code %||% "INTERNAL_ERROR"
  class <- switch(
    as.character(status),
    "401" = , "403" = "auth",
    "409" = "conflict",
    "413" = "limit",
    "501" = "capability",
    "410" = "protocol",
    "validation"
  )
  if (identical(code, "PROTOCOL_MISMATCH")) class <- "protocol"
  .at_abort(c("Control request failed ({code}).", "x" = "{err$message %||% ''}"),
            class = class, code = code,
            details = list(http_status = status, request_id = body$request_id,
                           retryable = isTRUE(err$retryable), error_details = err$details),
            call = call)
}

.control_call <- function(handle, method, path, query = "", body = NULL, request_id = NULL,
                          call = rlang::caller_env()) {
  .check_class(handle, "at_control_handle", call = call)
  body_raw <- if (is.null(body)) raw() else charToRaw(enc2utf8(as.character(
    jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", na = "null", digits = I(17))
  )))
  request_id <- request_id %||% paste0("request-", .uuid())
  if (identical(handle$kind, "local")) {
    hub <- .control_hub(handle, call = call)
    headers <- list(authorization = paste("Bearer", .control_tokens[[hub$instance_id]]),
                    `x-request-id` = request_id)
    if (!is.null(body)) headers$`content-type` <- "application/json"
    res <- .control_handle_request(hub, method, path, query, headers, body_raw,
                                   transport = "in_process")
    status <- res$status
    parsed <- .as_json_value(res$body)
  } else {
    token <- .control_remote_tokens[[paste0(handle$instance_id, "@", handle$port)]]
    if (is.null(token)) {
      .at_abort("This remote handle has no token in this R session; reconnect with {.fn at_control_connect}.",
                class = "auth", code = "AUTH_REQUIRED", call = call)
    }
    h <- curl::new_handle()
    hdr <- list(Authorization = paste("Bearer", token), `X-Request-Id` = request_id,
                Accept = "application/json")
    if (identical(method, "POST")) {
      hdr$`Content-Type` <- "application/json"
      curl::handle_setopt(h, post = TRUE, postfieldsize = length(body_raw),
                          postfields = body_raw)
    }
    do.call(curl::handle_setheaders, c(list(h), hdr))
    curl::handle_setopt(h, timeout = 30L)
    url <- sprintf("http://%s:%d%s%s", handle$host, handle$port, path,
                   if (nzchar(query)) paste0("?", query) else "")
    resp <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e) {
      .at_abort(c("The control service did not answer.", "x" = conditionMessage(e)),
                class = "io", code = "CONNECTION_FAILED", details = list(request_id = request_id),
                call = call)
    })
    status <- resp$status_code
    parsed <- tryCatch(jsonlite::fromJSON(rawToChar(resp$content), simplifyVector = FALSE),
                       error = function(e) NULL)
    if (is.null(parsed)) {
      .at_abort("The control service returned a non-JSON response.", class = "protocol",
                code = "INVALID_JSON", call = call)
    }
  }
  if (status >= 400L || !is.null(parsed$error)) {
    .control_raise(parsed, status, call)
  }
  .check_major_version(parsed$protocol_version, 1L, "control protocol", call = call)
  data <- parsed$data
  attr(data, "response") <- parsed[setdiff(names(parsed), "data")]
  data
}

#' Read the state of a control service
#'
#' @param handle An `at_control_handle`.
#' @param call The calling environment, for error reporting.
#' @return The state snapshot (a list) with `state_revision`, `event_cursor`,
#'   `queue`, `current` (image, layers, ROI summaries, annotation revision),
#'   `view`, `selection`, `staged`, `last_commit` and status fields.
#' @family control
#' @export
at_control_state <- function(handle, call = rlang::caller_env()) {
  .control_call(handle, "GET", "/v1/state", call = call)
}

#' Read control events after a cursor
#'
#' @param handle An `at_control_handle`.
#' @param after Optional event cursor (`"<instance_id>:<seq>"`); `NULL` returns
#'   the retained buffer. A cursor from another instance or older than the
#'   buffer yields `resync_required = TRUE`.
#' @param limit Maximum number of events to return.
#' @param call The calling environment, for error reporting.
#' @return A list with `events`, `next_cursor`, `resync_required`, `has_more`
#'   and `state_revision`.
#' @family control
#' @export
at_control_events <- function(handle, after = NULL, limit = 100L, call = rlang::caller_env()) {
  limit <- .check_count(limit, min = 1L, call = call)
  q <- paste0("limit=", limit)
  if (!is.null(after)) {
    .check_string(after, call = call)
    q <- paste0(q, "&after=", utils::URLencode(after, reserved = TRUE))
  }
  .control_call(handle, "GET", "/v1/events", query = q, call = call)
}

#' Send a typed control command
#'
#' Send one `annotatr-control-v1` operation. The command is a list with
#' `operation` (one of [at_control_capabilities()]`$operations`), `payload`
#' (a list) and `expected_revision` (the `state_revision` the command is based
#' on). `request_id` and `idempotency_key` are generated when absent and
#' `content_sha256` is always computed from the canonical payload. A stale
#' revision raises an `at_conflict_error` (`REVISION_CONFLICT`); re-sending the
#' same command with the same idempotency key returns the original result
#' (`replayed = TRUE` in the response) instead of applying it twice.
#'
#' @param handle An `at_control_handle`.
#' @param command A list with `operation`, `payload`, `expected_revision` and
#'   optionally `request_id`, `idempotency_key` and `extensions`.
#' @param call The calling environment, for error reporting.
#' @return The response `data` (a list) with the response envelope in
#'   `attr(, "response")`.
#' @family control
#' @seealso [at_control_request_status()]
#' @export
#' @examplesIf requireNamespace("httpuv", quietly = TRUE)
#' h <- at_control_start(at_example_session(3), serve = FALSE)
#' st <- at_control_state(h)
#' at_control_command(h, list(operation = "context.goto", payload = list(queue_index = 2),
#'                            expected_revision = st$state_revision))
#' at_control_stop(h)
at_control_command <- function(handle, command, call = rlang::caller_env()) {
  if (!is.list(command) || !.is_string(command$operation)) {
    .at_abort("{.arg command} must be a list with a string {.field operation}.", call = call)
  }
  ep <- Filter(function(e) identical(e$operation, command$operation), .control_endpoints())
  if (length(ep) == 0L) {
    .at_abort("Unknown control operation {.val {command$operation}}.", code = "ENDPOINT_NOT_FOUND",
              call = call)
  }
  payload <- command$payload %||% .json_object()
  if (is.list(payload) && length(payload) == 0L) payload <- .json_object()
  wire <- jsonlite::fromJSON(jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null",
                                              na = "null", digits = I(17)),
                             simplifyVector = FALSE)
  if (is.list(wire) && length(wire) == 0L) wire <- .json_object()
  body <- list(
    protocol = .contract$control,
    protocol_version = .contract$version,
    request_id = command$request_id %||% paste0("request-", .uuid()),
    expected_revision = if (is.null(command$expected_revision)) NULL else as.character(command$expected_revision),
    idempotency_key = command$idempotency_key %||% paste0("idem-", .uuid()),
    operation = command$operation,
    content_sha256 = .digest_json(wire),
    payload = payload,
    extensions = command$extensions %||% .json_object()
  )
  .control_call(handle, "POST", ep[[1]]$path, body = body, request_id = body$request_id,
                call = call)
}

#' Resolve the outcome of a control request
#'
#' After a lost response, ask the service what happened to a request id. An
#' unknown id raises `REQUEST_NOT_FOUND` and has no side effect.
#'
#' @param handle An `at_control_handle`.
#' @param request_id The `request_id` of the earlier command.
#' @param call The calling environment, for error reporting.
#' @return The request record: `request_id`, `operation`, `status`
#'   (`"completed"` or `"failed"`), `http_status`, timestamps, `extensions`
#'   and the stored `response`.
#' @family control
#' @export
at_control_request_status <- function(handle, request_id, call = rlang::caller_env()) {
  .check_string(request_id, call = call)
  if (!grepl("^[A-Za-z0-9._:-]{1,128}$", request_id)) {
    .at_abort("{.arg request_id} contains unsupported characters.", call = call)
  }
  .control_call(handle, "GET", paste0("/v1/requests/", request_id), call = call)
}
