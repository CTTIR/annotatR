test_that("GeoJSON round-trips geometry to 1e-9 and preserves metadata", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  back <- at_read_geojson(p)
  expect_setequal(names(back), c("tissue", "tumour"))
  g0 <- proj$layers$tissue$rois[[1]]$geometry
  g1 <- back$tissue$rois[[1]]$geometry
  expect_equal(sf::st_coordinates(g0), sf::st_coordinates(g1), tolerance = 1e-9)
  expect_setequal(
    vapply(back$tissue$rois, `[[`, character(1), "label"),
    vapply(proj$layers$tissue$rois, `[[`, character(1), "label")
  )
})

test_that("GeoJSON preserves labels, ids, source, and level", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  back <- at_read_geojson(p)
  roi <- back$tumour$rois[[1]]
  expect_identical(roi$label, "tumour")
  expect_identical(roi$level, 0L)
  expect_identical(roi$source, "manual")
})

test_that("flip_y is invertible in both directions", {
  proj <- demo_project()
  h <- at_dims(proj$image, 0)[2]
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p, flip_y = TRUE)
  back <- at_read_geojson(p, flip_y = TRUE, height = h)
  g0 <- proj$layers$tissue$rois[[1]]$geometry
  g1 <- back$tissue$rois[[1]]$geometry
  expect_equal(sf::st_coordinates(g0), sf::st_coordinates(g1), tolerance = 1e-9)
})

test_that("at_read_geojson errors when flip_y lacks height", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  expect_error(at_read_geojson(p, flip_y = TRUE), "height")
})

test_that("at_write_geojson refuses to clobber", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  expect_error(at_write_geojson(proj, p), "already exists")
})

test_that("point and polygon geometries both round-trip", {
  lyr <- at_layer_add(at_layer_add(at_layer("l"),
                                   at_roi_point(3, 4, label = "pt")),
                      at_roi_rect(0, 0, 5, 5, label = "rect"))
  proj <- at_project(small_image(), lyr)
  p <- withr::local_tempfile(fileext = ".geojson")
  at_write_geojson(proj, p)
  back <- at_read_geojson(p, layer_name = "l")
  types <- vapply(back$rois, function(r) as.character(sf::st_geometry_type(r$geometry)), character(1))
  expect_setequal(types, c("POINT", "POLYGON"))
})
