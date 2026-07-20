# helper local to this file
geom_type <- function(roi) as.character(sf::st_geometry_type(roi$geometry))

test_that("constructors produce the expected geometry types", {
  expect_identical(geom_type(at_roi_point(1, 2, label = "a")), "POINT")
  expect_identical(geom_type(at_roi_rect(0, 0, 4, 4, label = "a")), "POLYGON")
  expect_identical(geom_type(at_roi_circle(5, 5, 2, label = "a")), "POLYGON")
  expect_identical(geom_type(at_roi_ellipse(5, 5, 3, 2, label = "a")), "POLYGON")
  sq <- matrix(c(0, 0, 4, 0, 4, 4, 0, 4), ncol = 2, byrow = TRUE)
  expect_identical(geom_type(at_roi_polygon(sq, label = "a")), "POLYGON")
  expect_identical(
    geom_type(at_roi_freehand(cbind(c(0, 4, 2), c(0, 0, 4)), label = "a")),
    "POLYGON"
  )
})

test_that("rect validates ordering of bounds", {
  expect_error(at_roi_rect(4, 0, 0, 4, label = "a"), "xmax")
  expect_error(at_roi_rect(0, 4, 4, 0, label = "a"), "ymax")
})

test_that("area is correct and NA for non-areal geometry", {
  expect_equal(at_roi_area(at_roi_rect(0, 0, 10, 5, label = "a")), 50)
  expect_true(is.na(at_roi_area(at_roi_point(1, 1, label = "a"))))
  expect_equal(at_roi_area(donut_roi()), 100 - 16)
})

test_that("centroid and bbox are correct", {
  r <- at_roi_rect(0, 0, 10, 10, label = "a")
  expect_equal(at_roi_centroid(r), c(5, 5))
  expect_equal(at_roi_bbox(r), c(0, 0, 10, 10))
})

test_that("at_roi_rescale round-trips exactly", {
  r <- at_roi_rect(0, 0, 100, 100, label = "a")
  back <- at_roi_rescale(at_roi_rescale(r, 0, 2), 2, 0)
  expect_equal(
    sf::st_coordinates(r$geometry),
    sf::st_coordinates(back$geometry),
    tolerance = 1e-9
  )
  expect_identical(back$level, 0L)
})

test_that("rescale changes coordinates by the expected power-of-two factor", {
  r <- at_roi_point(100, 80, label = "a")
  r2 <- at_roi_rescale(r, 0, 2)
  co <- as.numeric(sf::st_coordinates(r2$geometry))
  expect_equal(co, c(25, 20))
  expect_identical(r2$level, 2L)
})

test_that("rescale does not modify its input (immutability)", {
  r <- at_roi_rect(0, 0, 100, 100, label = "a")
  snapshot <- r
  invisible(at_roi_rescale(r, 0, 2))
  expect_identical(r, snapshot)
})

test_that("buffer and simplify return annot_roi", {
  r <- at_roi_point(10, 10, label = "a")
  b <- at_roi_buffer(r, 5)
  expect_s3_class(b, "annot_roi")
  expect_gt(at_roi_area(b), 0)
  s <- at_roi_simplify(at_roi_circle(50, 50, 10, n_seg = 128, label = "a"), 1)
  expect_s3_class(s, "annot_roi")
})

test_that("invalid geometry is repaired with a warning", {
  bow <- matrix(c(0, 0, 10, 10, 10, 0, 0, 10, 0, 0), ncol = 2, byrow = TRUE)
  expect_warning(at_roi_polygon(bow, label = "bow"), "Repaired")
})

test_that("dots set reserved fields and store attributes", {
  r <- at_roi_point(1, 1, label = "a", source = "imported", grade = 3)
  expect_identical(r$source, "imported")
  expect_identical(r$attributes$grade, 3)
})

test_that("st_as_sf and st_geometry methods work", {
  r <- at_roi_rect(0, 0, 4, 4, label = "a")
  expect_s3_class(sf::st_as_sf(r), "sf")
  expect_s3_class(sf::st_geometry(r), "sfc")
})

test_that("plot returns a ggplot without drawing", {
  p <- plot(at_roi_rect(0, 0, 4, 4, label = "a"))
  expect_s3_class(p, "ggplot")
})

test_that("print and format produce output", {
  expect_output(print(at_roi_rect(0, 0, 4, 4, label = "a")), "annot_roi")
})
