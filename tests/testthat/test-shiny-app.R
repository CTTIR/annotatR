# Guard the full-app boot. The module servers are tested elsewhere, but the
# top-level app.R (which wires the UI theme and sources global.R) had no
# coverage, so a break there -- e.g. a symbol defined in global.R but not loaded
# before app.R uses it -- would only surface at launch. This builds the real
# app object exactly as the launcher does.

skip_if_not_installed("shiny")
skip_if_not_installed("bslib")
skip_if_not_installed("shinyjs")

test_that("the full app builds a shiny.appobj", {
  app_dir <- system.file("shiny", "annotatR", package = "annotatR")
  skip_if(!file.exists(file.path(app_dir, "app.R")), "app not installed")
  withr::local_options(annotatR.session = at_example_session(2))
  appobj <- withr::with_dir(app_dir, {
    source("app.R", local = new.env(parent = globalenv()))$value
  })
  expect_s3_class(appobj, "shiny.appobj")
})
