# Interchange with a real QuPath 0.7.0 installation. The fixtures were written
# and read by QuPath itself (tests/testthat/fixtures/qupath-0.7.0/README.md);
# expected values come from the QuPath script's inputs, not from annotatR.

fx <- function(...) test_path("fixtures", "qupath-0.7.0", ...)

expected_objects <- function() {
  jsonlite::read_json(fx("qupath_written_expected.json"))$objects
}

test_that("annotatR reads every object QuPath 0.7.0 wrote, with its identity and semantics", {
  exp <- expected_objects()
  lyr <- at_read_qupath(fx("qupath_written_objects.geojson"))
  expect_identical(length(lyr$rois), length(exp))
  for (k in seq_along(exp)) {
    e <- exp[[k]]
    r <- lyr$rois[[k]]
    expect_identical(r$id, e$id, label = e$key)
    expect_identical(r$attributes$qupath$object_id, e$id, label = e$key)
    expect_identical(r$attributes$qupath$object_type, e$object_type, label = e$key)
    cls <- e$classification$name %||% "unclassified"
    expect_identical(r$label, cls, label = e$key)
    expect_identical(isTRUE(r$attributes$locked), isTRUE(e$locked), label = e$key)
    if (e$plane$z > 0 || e$plane$t > 0) {
      expect_identical(r$attributes$plane, list(c = NA_integer_, z = as.integer(e$plane$z),
                                                t = as.integer(e$plane$t)), label = e$key)
    } else {
      expect_null(r$attributes$plane, label = e$key)
    }
  }
  cols <- lyr$style$colour
  expect_identical(toupper(cols[["Tumor"]]), sprintf("#%02X%02X%02X", 200L, 0L, 0L))
  expect_identical(toupper(cols[["Stroma"]]), sprintf("#%02X%02X%02X", 0L, 160L, 0L))
})

test_that("geometry, holes, lines, points and ellipses keep their declared fidelity", {
  exp <- expected_objects()
  lyr <- at_read_qupath(fx("qupath_written_objects.geojson"))
  by_key <- stats::setNames(lyr$rois, vapply(exp, `[[`, character(1), "key"))
  # (a) rectangle from its input x, y, w, h.
  bb <- at_roi_bbox(by_key$a)
  expect_equal(bb, c(exp[[1]]$roi$x, exp[[1]]$roi$y, exp[[1]]$roi$x + exp[[1]]$roi$w,
                     exp[[1]]$roi$y + exp[[1]]$roi$h))
  expect_equal(at_roi_area(by_key$a), 50 * 50)
  # (b) polygon with one hole: 80*80 - 30*30.
  expect_identical(length(by_key$b$geometry[[1]]), 2L)
  expect_equal(at_roi_area(by_key$b), 80 * 80 - 30 * 30)
  # (c) QuPath polygonises the ellipse and flags it; annotatR keeps the flag.
  expect_identical(by_key$c$attributes$qupath$roi_native, "ellipse")
  expect_identical(by_key$c$attributes$qupath$geometry_fidelity, "approximated")
  expect_identical(.geometry_fidelity(by_key$c), "approximated")
  # (d) measurements keep NaN as a value state, not a number or missing.
  ms <- by_key$d$attributes$qupath$measurements
  expect_identical(ms$name, c("Area px^2", "Mean"))
  expect_identical(ms$value_state, c("finite", "nan"))
  expect_true(is.nan(ms$value[2]))
  expect_identical(ms$value[1], 100)
  # (e) derived class and nucleus geometry.
  expect_identical(by_key$e$label, "Tumor: Positive")
  expect_identical(by_key$e$attributes$qupath$object_type, "cell")
  expect_identical(by_key$e$attributes$qupath$nucleus_geometry$type, "Polygon")
  # (f) line and (h) multipoint.
  expect_identical(as.character(sf::st_geometry_type(by_key$f$geometry)), "LINESTRING")
  pts <- sf::st_coordinates(by_key$h$geometry)[, c("X", "Y")]
  expect_equal(unname(pts), matrix(unlist(exp[[8]]$roi$points_as_passed), ncol = 2, byrow = TRUE))
})

test_that("QuPath's bare-array export reads identically to the FeatureCollection", {
  a <- at_read_qupath(fx("qupath_written_objects.geojson"))
  b <- at_read_qupath(fx("qupath_written_objects_array.geojson"))
  expect_identical(vapply(a$rois, `[[`, character(1), "id"), vapply(b$rois, `[[`, character(1), "id"))
  expect_identical(vapply(a$rois, function(r) .geometry_sha256(r$geometry), character(1)),
                   vapply(b$rois, function(r) .geometry_sha256(r$geometry), character(1)))
})

test_that("QuPath understood annotatR's legacy dialect but dropped non-UUID ids", {
  q <- jsonlite::read_json(fx("qupath_reads_annotatr.json"))
  expect_identical(q$n_objects_read, 4L)
  expect_false(any(vapply(q$objects, `[[`, logical(1), "id_equals_input")))
  expect_true(any(grepl("object_type", vapply(q$log_events, `[[`, character(1), "message"))))
  expect_identical(vapply(q$objects, `[[`, character(1), "object_type"),
                   c("annotation", "annotation", "annotation", "detection"))
  expect_identical(q$objects[[2]]$geometry$n_interior_rings, 1L)
})

test_that("the QuPath dialect writes what QuPath 0.7.0 reads natively and keeps annotatR ids", {
  lyr <- at_layer("regions", labels = c("Tumor", "Tumor: Positive"),
                  style = at_style(colour = c(Tumor = "#C80000", `Tumor: Positive` = "#C83232")))
  lyr <- at_layer_add(lyr, at_roi_rect(10, 20, 60, 70, label = "Tumor", id = "roi-a", locked = TRUE))
  lyr <- at_layer_add(lyr, at_roi_rect(1, 1, 5, 5, label = "Tumor: Positive", id = "roi-b"))
  img <- new_annot_image("x.tif", "raster", c(200L, 150L), 1L, list(c(200L, 150L)), 3L)
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_qupath(at_project(img, lyr), p)
  fc <- jsonlite::read_json(p)
  f1 <- fc$features[[1]]
  expect_identical(f1$properties$objectType, "annotation")
  expect_identical(unlist(f1$properties$classification$color), c(200L, 0L, 0L))
  expect_true(f1$properties$isLocked)
  expect_null(fc$features[[2]]$properties$isLocked)
  expect_identical(unlist(fc$features[[2]]$properties$classification$names), c("Tumor", "Positive"))
  expect_match(f1$id, "^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
  expect_identical(f1$id, .roi_uuid("roi-a"))
  expect_identical(.roi_uuid("11111111-1111-4111-8111-111111111111"),
                   "11111111-1111-4111-8111-111111111111")
  back <- at_read_qupath(p)
  expect_identical(vapply(back$rois, `[[`, character(1), "id"), c("roi-a", "roi-b"))
  expect_identical(back$rois[[2]]$label, "Tumor: Positive")
})

test_that("QuPath 0.7.0 keeps annotatR 0.2 ids and metadata through its own read and re-export", {
  q <- jsonlite::read_json(fx("qupath_reads_annotatr020.json"))
  sent <- jsonlite::read_json(fx("annotatr_020_qupath_dialect.geojson"))$features
  expect_identical(vapply(q$objects, function(o) o$id, character(1)),
                   vapply(sent, `[[`, character(1), "id"))
  expect_length(unlist(lapply(q$log_events %||% list(), `[[`, "message")), 0L)
  back <- at_read_qupath(fx("qupath_roundtrip_annotatr020.geojson"))
  expect_identical(vapply(back$rois, `[[`, character(1), "id"),
                   c("roi-rect-1", "roi-hole-2", "roi-point-3", "roi-plane-5", "roi-det-4"))
  labels <- vapply(back$rois, `[[`, character(1), "label")
  expect_identical(labels, c("Tumor", "Stroma", "Tumor", "Tumor: Positive", "Tumor"))
  expect_true(isTRUE(back$rois[[1]]$attributes$locked))
  expect_identical(back$rois[[4]]$attributes$plane$z, 2L)
  expect_identical(back$rois[[5]]$attributes$qupath$object_type, "detection")
  expect_equal(at_roi_area(back$rois[[2]]), 80 * 80 - 30 * 30)
})
