# annotatr-control-v1 through the shared dispatcher (in-process transport).
# The HTTP transport is exercised separately in test-control-http.R.
skip_if_not(requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE))

local_control <- function(n = 3L, ..., .env = parent.frame()) {
  h <- at_control_start(at_example_session(n), serve = FALSE, ...)
  withr::defer(suppressWarnings(tryCatch(at_control_stop(h), error = function(e) NULL)), envir = .env)
  h
}

cmd <- function(h, operation, payload = list(), rev = at_control_state(h)$state_revision, ...) {
  at_control_command(h, list(operation = operation, payload = payload, expected_revision = rev, ...))
}

raw_post <- function(h, path, body, token = .control_tokens[[h$instance_id]], headers = list()) {
  hdr <- utils::modifyList(list(authorization = paste("Bearer", token), `content-type` = "application/json"),
                           headers)
  txt <- if (is.character(body)) body else as.character(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null"))
  .control_handle_request(.control_hub(h), "POST", path, headers = hdr, body = charToRaw(txt),
                          transport = "in_process")
}

envelope <- function(operation, payload, rev, ...) {
  wire <- jsonlite::fromJSON(jsonlite::toJSON(payload, auto_unbox = TRUE), simplifyVector = FALSE)
  c(list(protocol = "annotatr-control-v1", protocol_version = "1.0",
         request_id = paste0("r-", .random_hex(4)), expected_revision = rev,
         idempotency_key = paste0("k-", .random_hex(4)), operation = operation,
         content_sha256 = .digest_json(if (length(wire)) wire else .json_object()),
         payload = if (length(payload)) payload else .json_object()), list(...))
}

schema_ok <- function(value, name) {
  expect_length(.schema_validate(.as_json_value(value), .schema_load("annotatr-control-v1", name)), 0L)
}

test_that("handshake, health, state and capabilities satisfy their schemas", {
  h <- local_control()
  hub <- .control_hub(h)
  tok <- .control_tokens[[h$instance_id]]
  for (path in c("/v1/handshake", "/v1/health", "/v1/state", "/v1/capabilities")) {
    res <- .control_handle_request(hub, "GET", path, headers = list(authorization = paste("Bearer", tok)),
                                   transport = "in_process")
    expect_identical(res$status, 200L, label = path)
    schema_ok(res$body, "response")
  }
  schema_ok(at_control_state(h), "state")
  hs <- .control_call(h, "GET", "/v1/handshake")
  schema_ok(hs, "handshake")
  expect_identical(hs$instance_id, h$instance_id)
  expect_identical(hs$coordinate_convention$y_axis, "down")
  health <- .control_call(h, "GET", "/v1/health")
  schema_ok(health, "health")
  expect_null(health$queue)
  expect_false(grepl(tok, jsonlite::toJSON(unclass(h), auto_unbox = TRUE, force = TRUE), fixed = TRUE))
  expect_false(grepl(tok, paste(readLines(h$manifest), collapse = ""), fixed = TRUE))
  expect_output(print(h), "<redacted>")
})

test_that("typed commands move the state revision and emit cursor-addressed events", {
  h <- local_control()
  st0 <- at_control_state(h)
  expect_identical(st0$state_revision, "0")
  g <- cmd(h, "context.goto", list(queue_index = 2))
  expect_identical(g$entry_id, "entry-0002")
  st1 <- at_control_state(h)
  expect_identical(st1$state_revision, "1")
  expect_identical(st1$current$queue_index, 2L)
  v <- cmd(h, "context.view", list(level = 0, bounds = list(0, 0, 100, 80), tool = "select",
                                   band_group = list(operation = "single", bands = list(2)),
                                   overlay = list(show = TRUE, mask_type = "multiclass", alpha = 0.3)))
  expect_identical(v$view$tool, "select")
  ev <- at_control_events(h, after = paste0(h$instance_id, ":1"))
  expect_identical(vapply(ev$events, `[[`, character(1), "type"), c("image.changed", "view.changed"))
  for (e in ev$events) schema_ok(e, "event")
  schema_ok(ev, "events-page")
  expect_false(ev$resync_required)
  none <- at_control_events(h, after = ev$next_cursor)
  expect_length(none$events, 0L)
  expect_identical(none$next_cursor, ev$next_cursor)
  expect_true(at_control_events(h, after = "instance-other:3")$resync_required)
  expect_identical(tryCatch(cmd(h, "context.view", list(bounds = list(0, 0, 9999, 10))),
                            error = function(e) e$code), "VALIDATION_FAILED")
  expect_identical(tryCatch(cmd(h, "context.view", list(band_group = list(operation = "eval", bands = list(1)))),
                            error = function(e) e$code), "VALIDATION_FAILED")
  expect_identical(tryCatch(cmd(h, "context.goto", list(queue_index = 9)), error = function(e) e$code),
                   "IMAGE_NOT_FOUND")
})

test_that("stale revisions conflict and idempotency keys replay without re-applying", {
  h <- local_control()
  rev <- at_control_state(h)$state_revision
  first <- cmd(h, "context.goto", list(queue_index = 2), rev = rev, idempotency_key = "idem-1",
               request_id = "req-1")
  expect_identical(at_control_state(h)$state_revision, "1")
  err <- tryCatch(cmd(h, "context.goto", list(queue_index = 3), rev = rev), error = function(e) e)
  expect_s3_class(err, "at_conflict_error")
  expect_identical(err$code, "REVISION_CONFLICT")
  expect_true(err$details$retryable)
  # Response loss: the client re-sends the same request with the same key.
  again <- cmd(h, "context.goto", list(queue_index = 2), rev = rev, idempotency_key = "idem-1",
               request_id = "req-1")
  expect_true(attr(again, "response")$replayed)
  expect_identical(at_control_state(h)$state_revision, "1")
  rec <- at_control_request_status(h, "req-1")
  schema_ok(rec, "request-record")
  expect_identical(rec$status, "completed")
  expect_identical(rec$operation, "context.goto")
  err <- tryCatch(cmd(h, "context.goto", list(queue_index = 3), rev = "1", idempotency_key = "idem-1"),
                  error = function(e) e)
  expect_identical(err$code, "IDEMPOTENCY_CONFLICT")
  expect_identical(tryCatch(at_control_request_status(h, "never-sent"), error = function(e) e$code),
                   "REQUEST_NOT_FOUND")
  expect_identical(at_control_state(h)$state_revision, "1")
})

test_that("envelopes are validated: version, fields, digest, operation and media type", {
  h <- local_control()
  good <- envelope("context.goto", list(queue_index = 2), "0")
  bad_major <- good; bad_major$protocol_version <- "2.0"
  expect_identical(raw_post(h, "/v1/context/goto", bad_major)$body$error$code, "PROTOCOL_MISMATCH")
  extra <- good; extra$surprise <- TRUE
  expect_identical(raw_post(h, "/v1/context/goto", extra)$body$error$code, "SCHEMA_INVALID")
  digest <- good; digest$content_sha256 <- strrep("0", 64)
  expect_identical(raw_post(h, "/v1/context/goto", digest)$body$error$code, "CONTENT_DIGEST_MISMATCH")
  expect_identical(raw_post(h, "/v1/context/view", good)$body$error$code, "VALIDATION_FAILED")
  expect_identical(raw_post(h, "/v1/context/goto", "not json")$body$error$code, "INVALID_JSON")
  res <- raw_post(h, "/v1/context/goto", good, headers = list(`content-type` = "text/plain"))
  expect_identical(res$status, 415L)
  with_ext <- envelope("context.goto", list(queue_index = 2), "0",
                       extensions = list(`org.example.trace` = list(span = "abc")))
  ok <- raw_post(h, "/v1/context/goto", with_ext)
  expect_identical(ok$status, 200L)
  rec <- at_control_request_status(h, with_ext$request_id)
  expect_identical(rec$extensions$`org.example.trace`$span, "abc")
  hub <- .control_hub(h)
  tok <- .control_tokens[[h$instance_id]]
  get405 <- .control_handle_request(hub, "GET", "/v1/context/goto",
                                    headers = list(authorization = paste("Bearer", tok)), transport = "in_process")
  expect_identical(get405$status, 405L)
  for (p in c("/v1/eval", "/v1/shell", "/v1/dom/click", "/v1/r")) {
    expect_identical(raw_post(h, p, good)$status, 404L)
  }
  big <- raw_post(h, "/v1/context/goto", paste0('{"x":"', strrep("a", 1100000), '"}'))
  expect_identical(big$body$error$code, "PAYLOAD_TOO_LARGE")
  expect_identical(big$status, 413L)
})

test_that("tokens, origins, hosts and TTL gate every request", {
  a <- local_control(1)
  b <- local_control(1)
  hub_a <- .control_hub(a)
  tok_b <- .control_tokens[[b$instance_id]]
  cross <- .control_handle_request(hub_a, "GET", "/v1/state",
                                   headers = list(authorization = paste("Bearer", tok_b)), transport = "in_process")
  expect_identical(cross$body$error$code, "TOKEN_INVALID")
  tok_a <- .control_tokens[[a$instance_id]]
  expect_identical(.control_handle_request(hub_a, "GET", "/v1/state",
                                           headers = list(authorization = paste("Bearer", tok_a),
                                                          origin = "http://evil.example"),
                                           transport = "in_process")$body$error$code, "ORIGIN_REJECTED")
  expect_identical(.control_handle_request(hub_a, "GET", "/v1/state",
                                           headers = list(authorization = paste("Bearer", tok_a),
                                                          host = "evil.example:80"))$body$error$code,
                   "HOST_REJECTED")
  expect_identical(.control_handle_request(hub_a, "GET", "/v1/state", headers = list(),
                                           transport = "in_process")$status, 401L)
  short <- local_control(1, ttl_seconds = 1L)
  Sys.sleep(1.3)
  err <- tryCatch(at_control_state(short), error = function(e) e)
  expect_s3_class(err, "at_auth_error")
  expect_identical(err$code, "TOKEN_EXPIRED")
  expect_error(at_control_start(at_example_session(1), host = "0.0.0.0", serve = FALSE),
               class = "at_auth_error")
  expect_error(at_control_start(at_example_session(1), control = "off", serve = FALSE))
})

test_that("an event gap beyond the retained buffer forces a resync", {
  base <- .interop_limits()
  local_mocked_bindings(.interop_limits = function() utils::modifyList(base, list(control_max_events_buffer = 3L)))
  h <- local_control(3)
  first <- at_control_events(h)$next_cursor
  for (i in 1:5) cmd(h, "context.selection", list(roi_ids = list()))
  ev <- at_control_events(h, after = first)
  expect_true(ev$resync_required)
  expect_length(ev$events, 3L)
})

test_that("annotations stage, commit and export through relative references only", {
  h <- local_control(1)
  hub <- .control_hub(h)
  proj <- at_example_project()
  partner <- file.path(hub$root, "incoming", "handoff")
  at_export_qupflowr(proj, partner, formats = "qupath_geojson")
  staged <- cmd(h, "annotations.stage", list(payload_ref = "incoming/handoff"))
  expect_identical(staged$summary$create, 3L)
  expect_identical(at_control_state(h)$annotation_status, "staged")
  expect_identical(tryCatch(cmd(h, "annotations.commit", list(patch_id = "wrong")), error = function(e) e$code),
                   "PATCH_NOT_FOUND")
  done <- cmd(h, "annotations.commit", list(patch_id = staged$patch_id), idempotency_key = "commit-1")
  expect_identical(done$applied, 3L)
  st <- at_control_state(h)
  expect_identical(st$annotation_status, "committed")
  expect_identical(length(st$current$rois), 3L)
  expect_true(file.exists(file.path(hub$session$out_dir, "_session.rds")))
  sel <- cmd(h, "context.selection", list(roi_ids = list(st$current$rois[[1]]$roi_id)))
  expect_length(sel$roi_ids, 1L)
  expect_identical(tryCatch(cmd(h, "context.selection", list(roi_ids = list("ghost"))),
                            error = function(e) e$code), "VALIDATION_FAILED")
  for (ref in c("../outside", "/etc/passwd", "incoming/../../x")) {
    expect_identical(tryCatch(cmd(h, "annotations.stage", list(payload_ref = ref)), error = function(e) e$code),
                     "PATH_OUTSIDE_ROOT", label = ref)
  }
  ex <- cmd(h, "export", list(destination = "handoff-1", formats = list("qupath_geojson", "mask_tiff")))
  expect_identical(ex$destination, "exports/handoff-1")
  expect_true(file.exists(file.path(hub$root, "exports", "handoff-1", "integrity.json")))
  expect_identical(tryCatch(cmd(h, "export", list(destination = "../x")), error = function(e) e$code),
                   "VALIDATION_FAILED")
  mp <- cmd(h, "mask.preview", list(mask_type = "labelled", max_dim = 32, include_png = TRUE))
  expect_identical(mp$preview_width <= 32L, TRUE)
  expect_match(mp$png_base64, "^[A-Za-z0-9+/=]+$")
  expect_identical(mp$mask_sha256, .sha256_bytes(writeBin(as.integer(as.matrix(at_mask(.hub_project(hub), "labelled"))),
                                                          raw(), size = 4L, endian = "little")))
})

test_that("read-only control sessions refuse mutations but allow viewing", {
  h <- local_control(2, read_only = TRUE)
  expect_identical(at_control_state(h)$mode, "read_only")
  cmd(h, "context.goto", list(queue_index = 2))
  expect_identical(tryCatch(cmd(h, "annotations.stage", list(features = list())), error = function(e) e$code),
                   "SCOPE_DENIED")
  expect_identical(tryCatch(cmd(h, "context.view", list(tool = "rect")), error = function(e) e$code),
                   "SCOPE_DENIED")
  expect_identical(tryCatch(cmd(h, "session.save", list()), error = function(e) e$code), "SCOPE_DENIED")
})

test_that("stop is owner-only, close stops only the service, and handles are process-bound", {
  h <- at_control_start(at_example_session(1), serve = FALSE)
  foreign <- h
  foreign$pid <- h$pid + 100000L
  expect_identical(tryCatch(at_control_stop(foreign), error = function(e) e$code), "NOT_OWNER")
  expect_identical(tryCatch(at_control_state(foreign), error = function(e) e$code), "NOT_OWNER")
  remote <- h
  remote$kind <- "remote"
  expect_identical(tryCatch(at_control_stop(remote), error = function(e) e$code), "NOT_OWNER")
  closed <- cmd(h, "close", list())
  expect_true(closed$closing)
  expect_identical(tryCatch(at_control_state(h), error = function(e) e$code), "SERVICE_CLOSED")
  man <- jsonlite::read_json(h$manifest)
  expect_identical(man$state, "stopped")
  expect_identical(man$stop_reason, "close requested")
  expect_false(at_control_stop(h))
})

test_that("the in-process listener answers real HTTP requests on the loopback port", {
  skip_if_not_installed("curl")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("later")
  root <- withr::local_tempdir()
  h <- at_control_start(at_example_session(1), root = root, token_file = file.path(root, "tok"))
  withr::defer(at_control_stop(h))
  expect_true(h$serving)
  tok <- readLines(file.path(root, "tok"))
  fetch <- function(path, headers) {
    result <- NULL
    hd <- curl::new_handle()
    do.call(curl::handle_setheaders, c(list(hd), headers))
    curl::curl_fetch_multi(sprintf("http://127.0.0.1:%d%s", h$port, path),
                           done = function(res) result <<- res, fail = function(msg) result <<- msg,
                           handle = hd)
    deadline <- Sys.time() + 10
    while (is.null(result) && Sys.time() < deadline) {
      curl::multi_run(timeout = 0.05, poll = TRUE)
      later::run_now(0.05)
    }
    result
  }
  ok <- fetch("/v1/health", list(Authorization = paste("Bearer", tok)))
  expect_identical(ok$status_code, 200L)
  body <- jsonlite::fromJSON(rawToChar(ok$content), simplifyVector = FALSE)
  expect_identical(body$data$instance_id, h$instance_id)
  expect_identical(fetch("/v1/state", list())$status_code, 401L)
  expect_identical(tryCatch(at_control_start(at_example_session(1), root = root,
                                             token_file = file.path(root, "tok"), serve = FALSE),
                            error = function(e) e$code), "DESTINATION_EXISTS")
})

test_that("remote connections are validated before any request and errors map to classes", {
  root <- withr::local_tempdir()
  h <- at_control_start(at_example_session(1), root = root, serve = FALSE)
  at_control_stop(h)
  tok <- file.path(root, "tok")
  writeLines(strrep("a", 64), tok)
  expect_identical(tryCatch(at_control_connect(h$manifest, tok), error = function(e) e$code), "SERVICE_CLOSED")
  man <- jsonlite::read_json(h$manifest)
  man$state <- "running"
  man$protocol <- "other"
  jsonlite::write_json(man, h$manifest, auto_unbox = TRUE, null = "null")
  expect_identical(tryCatch(at_control_connect(h$manifest, tok), error = function(e) e$code), "PROTOCOL_MISMATCH")
  man$protocol <- "annotatr-control-v1"
  man$host <- "0.0.0.0"
  jsonlite::write_json(man, h$manifest, auto_unbox = TRUE, null = "null")
  expect_identical(tryCatch(at_control_connect(h$manifest, tok), error = function(e) e$code), "HOST_REJECTED")
  man$host <- "127.0.0.1"
  jsonlite::write_json(man, h$manifest, auto_unbox = TRUE, null = "null")
  writeLines("not-a-token", tok)
  expect_identical(tryCatch(at_control_connect(h$manifest, tok), error = function(e) e$code), "TOKEN_INVALID")
  for (st in list(c("409", "at_conflict_error"), c("401", "at_auth_error"), c("413", "at_limit_error"),
                  c("501", "at_capability_error"), c("422", "at_validation_error"))) {
    err <- tryCatch(.control_raise(list(error = list(code = "X", message = "m"), request_id = "r"),
                                   as.integer(st[1]), rlang::current_env()), error = function(e) e)
    expect_s3_class(err, st[2])
  }
  remote <- structure(list(kind = "remote", instance_id = "instance-x", host = "127.0.0.1", port = 1L,
                           pid = 1L, manifest = "m", expires_at = "t", serving = TRUE),
                      class = "at_control_handle")
  expect_identical(tryCatch(at_control_state(remote), error = function(e) e$code), "AUTH_REQUIRED")
  expect_output(print(remote), "remote")
  expect_error(at_control_command(h, list(operation = "bogus")), class = "at_validation_error")
  expect_error(at_control_command(h, "context.goto"), class = "at_validation_error")
})
