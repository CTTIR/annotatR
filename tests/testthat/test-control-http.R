# The loopback HTTP transport, exercised from a separate R process: the service
# runs in a callr child (as a controlled app would), this process is the client.
skip_on_cran()
skip_if_not_installed("callr")
skip_if_not_installed("httpuv")
skip_if_not_installed("later")
skip_if_not_installed("curl")
skip_if_not(requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE))

# How the child process loads the same annotatR build as this test process: the
# source tree for a development load, otherwise the library this copy came from
# (e.g. a check or coverage library, whose installed R/ holds no .R sources).
pkg_loader <- function() {
  src <- normalizePath(test_path("..", ".."), mustWork = FALSE)
  if (file.exists(file.path(src, "DESCRIPTION")) &&
      length(list.files(file.path(src, "R"), pattern = "[.][Rr]$")) > 0L) {
    return(list(src = src, lib = NULL))
  }
  list(src = NULL, lib = dirname(find.package("annotatR")))
}

# Waits for the child's manifest list; a child that died first errors with its
# own error output instead of a bare missing-file error.
wait_for_child <- function(child, root, timeout = 60) {
  path <- file.path(root, "manifests.txt")
  deadline <- Sys.time() + timeout
  while (!file.exists(path) && child$is_alive() && Sys.time() < deadline) Sys.sleep(0.1)
  if (!file.exists(path)) {
    child$wait(2000)
    child_error <- paste(child$read_all_error(), collapse = "\n")
    cli::cli_abort(c("The control child did not start.", i = "{child_error}"))
  }
  TRUE
}

start_child <- function(root, n_services = 2L, ttl = 60L) {
  callr::r_bg(function(loader, root, n_services, ttl) {
    if (!is.null(loader$src)) {
      pkgload::load_all(loader$src, quiet = TRUE)
    } else {
      .libPaths(c(loader$lib, .libPaths()))
      library(annotatR)
    }
    handles <- lapply(seq_len(n_services), function(i) {
      at_control_start(at_example_session(2), root = file.path(root, paste0("svc", i)),
                       token_file = file.path(root, paste0("token", i)), ttl_seconds = ttl)
    })
    writeLines(vapply(handles, `[[`, character(1), "manifest"), file.path(root, "manifests.txt"))
    deadline <- Sys.time() + 120
    while (Sys.time() < deadline && !file.exists(file.path(root, "quit"))) later::run_now(0.05)
    for (h in handles) try(at_control_stop(h), silent = TRUE)
    "child finished"
  }, args = list(loader = pkg_loader(), root = root, n_services = n_services, ttl = ttl),
  supervise = TRUE)
}

http <- function(url, headers = list(), body = NULL) {
  h <- curl::new_handle()
  if (!is.null(body)) curl::handle_setopt(h, postfields = body)
  if (length(headers)) do.call(curl::handle_setheaders, c(list(h), headers))
  r <- curl::curl_fetch_memory(url, handle = h)
  list(status = r$status_code, body = jsonlite::fromJSON(rawToChar(r$content), simplifyVector = FALSE))
}

test_that("two controlled instances in another process are isolated and speak the protocol over HTTP", {
  root <- withr::local_tempdir()
  child <- start_child(root)
  withr::defer({
    file.create(file.path(root, "quit"))
    child$wait(5000)
    if (child$is_alive()) child$kill()
  })
  expect_true(wait_for_child(child, root))
  manifests <- readLines(file.path(root, "manifests.txt"))
  skip_on_os("windows")
  expect_identical(file.info(file.path(root, "token1"))$mode, as.octmode("600"))

  a <- at_control_connect(manifests[1], file.path(root, "token1"))
  b <- at_control_connect(manifests[2], file.path(root, "token2"))
  expect_false(identical(a$port, b$port))
  expect_false(identical(a$instance_id, b$instance_id))
  expect_identical(a$pid, b$pid)
  expect_false(identical(a$pid, Sys.getpid()))

  st <- at_control_state(a)
  expect_identical(st$state_revision, "0")
  g <- at_control_command(a, list(operation = "context.goto", payload = list(queue_index = 2),
                                  expected_revision = "0", request_id = "http-req-1",
                                  idempotency_key = "http-key-1"))
  expect_identical(g$entry_id, "entry-0002")
  expect_identical(at_control_state(b)$state_revision, "0")
  # Response loss: resolve by request id, then a re-send replays without a new revision.
  expect_identical(at_control_request_status(a, "http-req-1")$status, "completed")
  replay <- at_control_command(a, list(operation = "context.goto", payload = list(queue_index = 2),
                                       expected_revision = "0", request_id = "http-req-1",
                                       idempotency_key = "http-key-1"))
  expect_true(attr(replay, "response")$replayed)
  expect_identical(at_control_state(a)$state_revision, "1")
  err <- tryCatch(at_control_command(a, list(operation = "context.goto", payload = list(queue_index = 1),
                                             expected_revision = "0")), error = function(e) e)
  expect_identical(err$code, "REVISION_CONFLICT")

  url <- sprintf("http://127.0.0.1:%d/v1/state", a$port)
  tok_a <- readLines(file.path(root, "token1"))
  tok_b <- readLines(file.path(root, "token2"))
  expect_identical(http(url)$status, 401L)
  expect_identical(http(url, list(Authorization = paste("Bearer", tok_b)))$body$error$code, "TOKEN_INVALID")
  expect_identical(http(url, list(Authorization = paste("Bearer", tok_a), Origin = "http://evil.example"))$status,
                   403L)
  expect_identical(http(url, list(Authorization = paste("Bearer", tok_a), Host = "evil.example"))$body$error$code,
                   "HOST_REJECTED")
  expect_identical(http(sprintf("http://127.0.0.1:%d/v1/eval", a$port),
                        list(Authorization = paste("Bearer", tok_a), `Content-Type` = "application/json"),
                        body = "{}")$status, 404L)
  big <- http(sprintf("http://127.0.0.1:%d/v1/context/goto", a$port),
              list(Authorization = paste("Bearer", tok_a), `Content-Type` = "application/json"),
              body = paste0('{"pad":"', strrep("x", 2e6), '"}'))
  expect_identical(big$status, 413L)
  expect_false(grepl(tok_a, paste(readLines(manifests[1]), collapse = ""), fixed = TRUE))

  # This process does not own the service: stop is refused; close stops only that service.
  expect_identical(tryCatch(at_control_stop(a), error = function(e) e$code), "NOT_OWNER")
  expect_true(at_control_close(a)$closing)
  Sys.sleep(1)
  expect_identical(tryCatch(at_control_state(a), error = function(e) e$code), "CONNECTION_FAILED")
  expect_identical(jsonlite::read_json(manifests[1])$state, "stopped")
  expect_true(child$is_alive())
  expect_identical(at_control_state(b)$state_revision, "0")
})

test_that("an expired TTL stops the listener and marks the manifest expired", {
  root <- withr::local_tempdir()
  child <- start_child(root, n_services = 1L, ttl = 2L)
  withr::defer({
    file.create(file.path(root, "quit"))
    child$wait(5000)
    if (child$is_alive()) child$kill()
  })
  expect_true(wait_for_child(child, root))
  mf <- readLines(file.path(root, "manifests.txt"))
  a <- at_control_connect(mf, file.path(root, "token1"))
  Sys.sleep(3)
  err <- tryCatch(at_control_state(a), error = function(e) e$code)
  expect_true(err %in% c("TOKEN_EXPIRED", "CONNECTION_FAILED"))
  deadline <- Sys.time() + 5
  while (!identical(jsonlite::read_json(mf)$state, "expired") && Sys.time() < deadline) Sys.sleep(0.2)
  expect_identical(jsonlite::read_json(mf)$state, "expired")
  expect_identical(tryCatch(at_control_connect(mf, file.path(root, "token1")), error = function(e) e$code),
                   "SERVICE_CLOSED")
})
