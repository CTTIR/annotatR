skip_if_not_installed("httpuv")
skip_if_not_installed("later")

control_loop_fixture <- function(ttl = 900L) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  h <- at_control_start(at_example_session(1), root = root, ttl_seconds = ttl)
  withr::defer(at_control_stop(h), envir = parent.frame())
  h
}

test_that("stopping a listener removes its pending expiry callback", {
  later::with_temp_loop({
    h <- control_loop_fixture()
    expect_false(later::loop_empty())
    expect_true(at_control_stop(h))
    later::run_now(0)
    expect_true(later::loop_empty())
    expect_false(at_control_stop(h))
  })
})

test_that("stopping a listener leaves unrelated callbacks intact", {
  later::with_temp_loop({
    cancel_other <- later::later(function() NULL, delay = 60)
    h <- control_loop_fixture()
    at_control_stop(h)
    later::run_now(0)
    expect_false(later::loop_empty())
    expect_true(cancel_other())
    expect_true(later::loop_empty())
  })
})

test_that("a serving listener still expires automatically", {
  later::with_temp_loop({
    h <- control_loop_fixture(ttl = 1L)
    hub <- .control_hub(h)
    deadline <- Sys.time() + 5
    while (identical(hub$status, "running") && Sys.time() < deadline) {
      later::run_now(0.1)
    }
    expect_identical(hub$status, "stopped")
    manifest <- jsonlite::read_json(h$manifest)
    expect_identical(manifest$state, "expired")
    expect_identical(manifest$stop_reason, "ttl expired")
    expect_true(later::loop_empty())
  })
})
