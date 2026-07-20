# The general rasterisation path (eps-shifted stars), bypassing the fast path.
general_cover <- function(geom, dims) {
  g <- .apply_coords(geom, function(m) cbind(m[, 1] - 1e-7, m[, 2] - 1e-7))
  .cover_stars(g, dims, FALSE)
}

mkrect <- function(x0, y0, x1, y1) {
  sf::st_polygon(list(rbind(c(x0, y0), c(x1, y0), c(x1, y1), c(x0, y1), c(x0, y0))))
}

test_that("the rectangle short-circuit is bit-identical to the general path", {
  cases <- list(c(2, 2, 5, 5), c(2.5, 2.5, 5.5, 5.5), c(0, 0, 10, 10),
                c(1.3, 2.7, 8.9, 6.1), c(2.6, 2.6, 4.4, 4.4), c(0, 0, 1, 1))
  for (cc in cases) {
    r <- mkrect(cc[1], cc[2], cc[3], cc[4])
    expect_identical(.cover_shortcircuit(r, c(10, 10)), general_cover(r, c(10, 10)),
                     info = paste(cc, collapse = ","))
  }
})

test_that("the point short-circuit is bit-identical to the general path", {
  for (p in list(c(5, 5), c(5.3, 7.8), c(1, 1), c(9.5, 2.5))) {
    pt <- sf::st_point(p)
    expect_identical(.cover_shortcircuit(pt, c(10, 10)), general_cover(pt, c(10, 10)))
  }
})

test_that("non-rectangular polygons fall through the fast path", {
  tri <- sf::st_polygon(list(rbind(c(1, 1), c(8, 1), c(4, 7), c(1, 1))))
  expect_null(.cover_shortcircuit(tri, c(10, 10)))
})

test_that("batched rasterisation equals the per-ROI path", {
  a <- at_roi_circle(5, 5, 3, label = "a")
  b <- at_roi_circle(7, 7, 3, label = "b")
  lyr <- at_layer_add(at_layer_add(at_layer("l"), a), b)
  entries <- .collect_mask_rois(lyr, level = 0L)
  values <- seq_along(entries)
  for (rev in c(FALSE, TRUE)) {
    batched <- .rasterize_batch(entries, values, c(12, 12), 0L, FALSE, reverse = rev)
    per_roi <- .rasterize_per_roi(entries, values, c(12, 12), 0L, FALSE,
                                  if (rev) "first" else "last", "stars")
    expect_identical(batched, per_roi, info = paste("reverse =", rev))
  }
})

test_that("the tile cache returns identical data and can be cleared", {
  .tile_cache_clear()
  arr <- array(seq_len(8 * 8 * 2), dim = c(8, 8, 2))
  img <- new_annot_image("c.tif", "raster", c(8L, 8L), 1L, list(c(8L, 8L)), 2L,
                         handle = list(data = arr))
  a1 <- at_tile(img)
  a2 <- at_tile(img)
  expect_identical(a1, a2)
  key <- .tile_key(img, 0L, c(1L, 8L), c(1L, 8L), NULL)
  expect_false(is.null(.tile_cache_get(key)))
  .tile_cache_clear()
  expect_null(.tile_cache_get(key))
})

test_that("extracting a small ROI from a large image stays tile-wise", {
  skip_on_cran()
  arr <- array(runif(2048 * 2048), dim = c(2048, 2048, 1)) # ~32 MB
  img <- new_annot_image("big.tif", "raster", c(2048L, 2048L), 1L,
                         list(c(2048L, 2048L)), 1L, handle = list(data = arr))
  .tile_cache_clear()
  proj <- at_project(img, at_layer_add(at_layer("l"),
                                       at_roi_rect(10, 10, 40, 40, label = "a")))
  invisible(gc(reset = TRUE, full = TRUE))
  before <- gc()["Vcells", "max used"]
  ex <- at_extract(proj, stat = "mean")
  after <- gc()["Vcells", "max used"]
  # A 30x30 tile-wise extraction must allocate far less than the whole image
  # (2048^2 = ~4.2M Vcells).
  expect_lt(after - before, 2048 * 2048 / 2)
  expect_equal(ex$n_px, 900L)
})

test_that("the tile cache evicts the least-recently-used entry over the limit", {
  withr::local_options(annotatR.cache_size = 2000) # bytes: tiny
  .tile_cache_clear()
  for (i in 1:5) {
    arr <- array(as.numeric(i), dim = c(8, 8, 1))
    img <- new_annot_image(paste0("e", i, ".tif"), "raster", c(8L, 8L), 1L,
                           list(c(8L, 8L)), 1L, handle = list(data = arr))
    at_tile(img)
  }
  expect_lte(.tile_cache$bytes, 2000 * 3) # bounded, not unbounded growth
  .tile_cache_clear()
})
