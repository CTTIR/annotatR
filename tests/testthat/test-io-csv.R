test_that("CSV/WKT round-trips geometry and labels", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".csv")
  at_write_rois_csv(proj, p)
  lyr <- at_read_rois_csv(p)
  expect_identical(at_layer_n(lyr), 3L)
  g0 <- at_rois(proj)$geometry[[1]]
  g1 <- lyr$rois[[1]]$geometry[[1]]
  expect_equal(sf::st_coordinates(sf::st_sfc(g0)),
               sf::st_coordinates(sf::st_sfc(g1)), tolerance = 1e-6)
  expect_setequal(vapply(lyr$rois, `[[`, character(1), "label"),
                  at_rois(proj)$label)
})

test_that("at_read_rois_csv requires label and geometry columns", {
  p <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(data.frame(a = 1, b = 2), p, row.names = FALSE)
  expect_error(at_read_rois_csv(p), "label")
})

test_that("at_write_rois_csv refuses to clobber", {
  proj <- demo_project()
  p <- withr::local_tempfile(fileext = ".csv")
  at_write_rois_csv(proj, p)
  expect_error(at_write_rois_csv(proj, p), "already exists")
})

test_that("empty project writes an empty CSV that reads back to an empty layer", {
  p <- withr::local_tempfile(fileext = ".csv")
  at_write_rois_csv(at_project(small_image()), p)
  lyr <- at_read_rois_csv(p)
  expect_identical(at_layer_n(lyr), 0L)
})
