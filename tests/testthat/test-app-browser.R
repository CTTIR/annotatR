# Real-browser journeys (shinytest2 + chromote). They drive the actual canvas
# JavaScript with DOM mouse and keyboard events and assert server state and
# downloaded files. Prerequisite: a Chromium-based browser (set CHROMOTE_CHROME)
# and ANNOTATR_BROWSER_TESTS=true; without them the lane is reported as skipped.
skip_on_cran()
skip_if_not_installed("shinytest2")
skip_if_not_installed("chromote")
skip_if_not_installed("magick")
skip_if(!identical(Sys.getenv("ANNOTATR_BROWSER_TESTS"), "true"),
        "browser lane not requested (set ANNOTATR_BROWSER_TESTS=true; open: real-browser evidence)")
skip_if(is.null(tryCatch(chromote::find_chrome(), error = function(e) NULL)),
        "no Chromium-based browser found (set CHROMOTE_CHROME; open: real-browser evidence)")

# Hosts that disable unprivileged user namespaces (e.g. Ubuntu 23.10+ AppArmor)
# cannot start Chromium's sandbox; ANNOTATR_CHROME_NO_SANDBOX=true opts this local
# lane into --no-sandbox. The browser only loads the local test app.
if (identical(Sys.getenv("ANNOTATR_CHROME_NO_SANDBOX"), "true")) {
  old_args <- chromote::get_chrome_args()
  chromote::set_chrome_args(unique(c(old_args, "--no-sandbox")))
  withr::defer(chromote::set_chrome_args(old_args), teardown_env())
}

pkg_root <- function() normalizePath(test_path("..", ".."))

# An app directory that loads this source tree and builds the app via at_app().
browser_app_dir <- function(session_rds, extra = "") {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  writeLines(c(
    sprintf("pkgload::load_all(%s, quiet = TRUE, export_all = FALSE)", deparse(pkg_root())),
    extra,
    sprintf("annotatR::at_app(session = readRDS(%s))", deparse(session_rds))
  ), file.path(dir, "app.R"))
  dir
}

browser_session <- function(dir) {
  file.copy(c(at_example_path("cube"), sub("\\.hdr$", ".dat", at_example_path("cube"))), dir)
  file.copy(at_example_path("tissue"), file.path(dir, "tissue.png"))
  s <- at_session(c(file.path(dir, "example_cube.hdr"), file.path(dir, "tissue.png")),
                  labels = c("tumour", "stroma"), out_dir = file.path(dir, "out"))
  s$autosave <- FALSE
  path <- file.path(dir, "session.rds")
  saveRDS(s, path)
  path
}

# Dispatch real mouse events on the canvas, in fractions of its size.
drag_js <- function(x0, y0, x1, y1) {
  sprintf("(function(){var c=document.querySelector('#canvas-canvas canvas');var r=c.getBoundingClientRect();
    function ev(t,fx,fy){c.dispatchEvent(new MouseEvent(t,{bubbles:true,clientX:r.left+fx*r.width,clientY:r.top+fy*r.height}));}
    ev('mousedown',%f,%f);ev('mousemove',%f,%f);ev('mouseup',%f,%f);})();", x0, y0, x1, y1, x1, y1)
}
key_js <- function(key, shift = FALSE) {
  sprintf("document.dispatchEvent(new KeyboardEvent('keydown',{key:'%s',shiftKey:%s,bubbles:true}));",
          key, if (shift) "true" else "false")
}

value <- function(app, name) app$get_value(export = name)
canvas_uri <- function(app) {
  out <- app$get_value(output = "canvas-canvas")
  if (is.character(out)) out <- jsonlite::fromJSON(out, simplifyVector = FALSE)
  out$x$tileSource$dataUri
}

test_that("draw, navigate by keyboard, change bands, probe, overlay, stage, commit, download and theme", {
  work <- withr::local_tempdir()
  sess_rds <- browser_session(work)
  app <- shinytest2::AppDriver$new(browser_app_dir(sess_rds), name = "annotatr-journey",
                                   load_timeout = 90000, timeout = 30000, height = 1000, width = 1400)
  withr::defer(app$stop())
  app$wait_for_js("document.querySelector('#canvas-canvas canvas') !== null", timeout = 60000)
  expect_identical(value(app, "cursor"), 1L)
  expect_identical(value(app, "n_rois"), 0L)

  app$click("canvas-tool_rect")
  app$wait_for_value(export = "tool", ignore = list("pan"))
  app$run_js(drag_js(0.3, 0.3, 0.6, 0.6))
  app$wait_for_value(export = "n_rois", ignore = list(0L))
  expect_identical(value(app, "n_rois"), 1L)
  expect_identical(value(app, "annotation_status"), "unsaved")

  app$run_js(key_js("n"))
  app$wait_for_value(export = "cursor", ignore = list(1L))
  expect_identical(value(app, "n_rois"), 0L)
  app$run_js(key_js("p"))
  app$wait_for_value(export = "cursor", ignore = list(2L))
  expect_identical(value(app, "n_rois"), 1L)

  before_uri <- canvas_uri(app)
  app$set_inputs(`view-mode` = "single")
  app$set_inputs(`view-b1` = "35")
  app$click("view-apply")
  app$wait_for_value(export = "view_operation", ignore = list("natural"))
  expect_identical(value(app, "view_operation"), "single")
  app$wait_for_idle()
  after_uri <- canvas_uri(app)
  expect_false(identical(before_uri, after_uri))

  app$click("canvas-tool_probe")
  app$wait_for_value(export = "tool", ignore = list("rect"))
  app$run_js(sprintf("(function(){var c=document.querySelector('#canvas-canvas canvas');var r=c.getBoundingClientRect();
    c.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,clientX:r.left+r.width/2,clientY:r.top+r.height/2}));})();"))
  app$wait_for_value(export = "probe")
  expect_length(value(app, "probe"), 2L)

  app$set_inputs(`mask-overlay` = TRUE)
  app$wait_for_value(export = "overlay_on", ignore = list(FALSE))

  handoff <- file.path(work, "partner")
  proj <- at_project(at_read_image(file.path(work, "example_cube.hdr")),
                     at_layer_add(at_layer("annotations", labels = "tumour"),
                                  at_roi_rect(2, 2, 20, 20, label = "tumour", id = "partner-roi")))
  at_export_qupflowr(proj, handoff, formats = "qupath_geojson")
  app$set_inputs(nav = "Data")
  app$set_inputs(`data-handoff` = handoff)
  app$click("data-stage")
  app$wait_for_value(export = "staged", ignore = list(FALSE))
  app$set_inputs(nav = "Annotate")
  app$wait_for_js("document.querySelector('#staging-commit') !== null")
  app$click("staging-commit")
  app$wait_for_value(export = "annotation_status", ignore = list("staged", "unsaved", "saved"))
  expect_identical(value(app, "annotation_status"), "committed")
  expect_identical(value(app, "n_rois"), 2L)
  expect_true(app$get_js("document.querySelector('[data-state=\"committed\"]') !== null"))

  app$set_inputs(nav = "Summary")
  app$set_inputs(`region-extent` = "custom")
  app$wait_for_js("document.querySelector('#region-xmin') !== null")
  app$set_inputs(`region-xmin` = 0, `region-ymin` = 0, `region-xmax` = 8, `region-ymax` = 4)
  zipfile <- app$get_download("region-download")
  listed <- utils::unzip(zipfile, list = TRUE)$Name
  expect_setequal(listed, c("region.dat", "region.hdr", "region.json"))
  ex <- withr::local_tempdir()
  utils::unzip(zipfile, exdir = ex)
  region <- at_read_image(file.path(ex, "region.hdr"))
  src <- at_read_image(file.path(work, "example_cube.hdr"))
  expect_equal(at_tile(region), at_tile(src, xrange = c(1, 8), yrange = c(1, 4)), tolerance = 0)

  app$set_inputs(nav = "Export")
  app$wait_for_js("(function(){var a=document.querySelector('#export-run');return a !== null && !!a.getAttribute('href');})()")
  exp_zip <- app$get_download("export-run")
  expect_true(any(grepl("\\.geojson$", utils::unzip(exp_zip, list = TRUE)$Name)))

  theme <- function() app$get_js("document.documentElement.getAttribute('data-bs-theme')")
  start <- theme()
  app$run_js("document.querySelector('bslib-input-dark-mode').shadowRoot.querySelector('button').click();")
  app$wait_for_js(sprintf("document.documentElement.getAttribute('data-bs-theme') !== '%s'", start))
  expect_false(identical(theme(), start))
})

test_that("a saved session resumes in a fresh app with its annotations", {
  work <- withr::local_tempdir()
  sess_rds <- browser_session(work)
  app <- shinytest2::AppDriver$new(browser_app_dir(sess_rds), name = "annotatr-resume",
                                   load_timeout = 90000, timeout = 30000, width = 1400, height = 1000)
  app$wait_for_js("document.querySelector('#canvas-canvas canvas') !== null", timeout = 60000)
  app$click("canvas-tool_rect")
  app$run_js(drag_js(0.2, 0.2, 0.5, 0.5))
  app$wait_for_value(export = "n_rois", ignore = list(0L))
  app$run_js(key_js("s"))
  app$wait_for_value(export = "saved", ignore = list("unsaved", "saving"))
  saved <- file.path(work, "out", "_session.rds")
  expect_true(file.exists(saved))
  app$stop()
  resumed <- at_resume(saved)
  expect_identical(nrow(at_rois(resumed$projects[[1]])), 1L)
  saveRDS(resumed, file.path(work, "resumed.rds"))
  app2 <- shinytest2::AppDriver$new(browser_app_dir(file.path(work, "resumed.rds")), name = "annotatr-resumed",
                                    load_timeout = 90000, timeout = 30000, width = 1400, height = 1000)
  withr::defer(app2$stop())
  app2$wait_for_js("document.querySelector('#canvas-canvas canvas') !== null", timeout = 60000)
  expect_identical(value(app2, "n_rois"), 1L)
})

test_that("a browser app attached to the control service follows commands and reports edits", {
  skip_if_not_installed("curl")
  work <- withr::local_tempdir()
  sess_rds <- browser_session(work)
  root <- file.path(work, "control")
  dir <- withr::local_tempdir()
  writeLines(c(
    sprintf("pkgload::load_all(%s, quiet = TRUE, export_all = FALSE)", deparse(pkg_root())),
    sprintf("h <- annotatR::at_control_start(readRDS(%s), root = %s, token_file = %s, ttl_seconds = 600L)",
            deparse(sess_rds), deparse(root), deparse(file.path(work, "token"))),
    sprintf("writeLines(h$manifest, %s)", deparse(file.path(work, "manifest.txt"))),
    "annotatR::at_app(control = h)"
  ), file.path(dir, "app.R"))
  app <- shinytest2::AppDriver$new(dir, name = "annotatr-control", load_timeout = 90000, timeout = 30000,
                                   width = 1400, height = 1000)
  withr::defer(app$stop())
  app$wait_for_js("document.querySelector('#canvas-canvas canvas') !== null", timeout = 60000)
  ctl <- at_control_connect(readLines(file.path(work, "manifest.txt")), file.path(work, "token"))
  st <- at_control_state(ctl)
  at_control_command(ctl, list(operation = "context.goto", payload = list(queue_index = 2),
                               expected_revision = st$state_revision))
  app$wait_for_value(export = "cursor", ignore = list(1L), timeout = 20000)
  expect_identical(value(app, "cursor"), 2L)
  after <- at_control_events(ctl)$next_cursor
  app$click("canvas-tool_rect")
  app$run_js(drag_js(0.3, 0.3, 0.7, 0.7))
  app$wait_for_value(export = "n_rois", ignore = list(0L))
  deadline <- Sys.time() + 10
  types <- character()
  while (!"annotations.edited" %in% types && Sys.time() < deadline) {
    types <- vapply(at_control_events(ctl, after = after)$events, `[[`, character(1), "type")
    Sys.sleep(0.3)
  }
  expect_true("annotations.edited" %in% types)
  expect_identical(length(at_control_state(ctl)$current$rois), 1L)
})
