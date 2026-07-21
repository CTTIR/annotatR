# A penumbra "along the injury" is an annulus straddling the injury margin: the
# headline HSI use case. at_roi_ring() makes it a one-liner over buffer +
# difference.

test_that("a ring is the external band around an ROI margin", {
  inj <- at_roi_rect(10, 10, 20, 20, label = "injury") # 10x10 square, area 100
  ring <- at_roi_ring(inj, outer = 2, label = "penumbra")
  expect_s3_class(ring, "annot_roi")
  expect_identical(ring$label, "penumbra")
  a <- as.numeric(sf::st_area(ring$geometry))
  expect_gt(a, 70) # ~92.6 (perimeter*2 + pi*2^2)
  expect_lt(a, 100)
  # The injury interior is a hole in the ring.
  ctr <- sf::st_sfc(sf::st_point(c(15, 15)))
  expect_false(as.logical(sf::st_intersects(ring$geometry, ctr, sparse = FALSE)))
  # A point just outside the margin is inside the ring.
  out <- sf::st_sfc(sf::st_point(c(21, 15)))
  expect_true(as.logical(sf::st_intersects(ring$geometry, out, sparse = FALSE)))
})

test_that("a ring can straddle the margin (inner band included)", {
  inj <- at_roi_rect(10, 10, 20, 20, label = "injury")
  ring <- at_roi_ring(inj, outer = 2, inner = 2, label = "penumbra")
  # Deep interior stays a hole; a point just inside the margin is in the band.
  ctr <- sf::st_sfc(sf::st_point(c(15, 15)))
  inner_edge <- sf::st_sfc(sf::st_point(c(11, 15)))
  expect_false(as.logical(sf::st_intersects(ring$geometry, ctr, sparse = FALSE)))
  expect_true(as.logical(sf::st_intersects(ring$geometry, inner_edge, sparse = FALSE)))
})

test_that("at_roi_ring validates its distances", {
  inj <- at_roi_rect(10, 10, 20, 20, label = "injury")
  expect_error(at_roi_ring(inj, outer = -1), "outer")
})
