# Proposed audit contracts and independent oracles: planning/REGRESSIONS.md.
test_that("A05 triangle coverage uses a deterministic pixel-centre tie rule", {
  # Evaluate membership at (x + epsilon, y + epsilon^2), epsilon -> 0+.
  # For this triangle y = x is included: five rows contain 5,4,3,2,1 pixels.
  expected <- matrix(FALSE, 10, 10)
  expected[1:5, 1:5] <- matrix(c(
    1,1,1,1,1,
    0,1,1,1,1,
    0,0,1,1,1,
    0,0,0,1,1,
    0,0,0,0,1), 5, 5, byrow = TRUE) != 0
  tri <- at_roi_polygon(rbind(c(0,0), c(5,0), c(5,5)), "tri")
  layer <- at_layer_add(at_layer_add(at_layer("L"), tri), at_roi_point(9,9,"extra"))
  expect_identical(as.matrix(at_mask(tri, dims = c(10,10))), expected)
  expect_identical(as.matrix(at_mask(layer, type = "labelled", dims = c(10,10))) == 1L,
                   expected)
})

for (fmt in c("json", "csv")) {
  test_that(paste("A06", fmt, "interchange preserves level-zero geometry"), {
    p <- at_add_roi(at_project(small_image(), at_layer("L")), "L",
                    at_roi_rect(2,2,5,5,"a",level = 1L))
    path <- tempfile(fileext = paste0(".", fmt))
    withr::defer(unlink(path))
    if (fmt == "json") {
      at_write_geojson(p, path)
      layer <- at_read_geojson(path)[[1]]
    } else {
      at_write_rois_csv(p, path)
      layer <- at_read_rois_csv(path)
    }
    rt <- at_rois(at_project(p$image, layer))
    expect_equal(rt$area_px, 36)
    expect_equal(unname(sf::st_bbox(rt$geometry)), c(4,4,10,10), ignore_attr = TRUE)
  })
}

test_that("A15 integer point extraction includes its containing pixel", {
  img <- tiny_image()
  img$handle <- list(data = array(seq_len(100), c(10,10,1)))
  .tile_cache_clear()
  withr::defer(.tile_cache_clear())
  p <- at_project(img, at_layer_add(at_layer("L"), at_roi_point(5,5,"a")))
  expected <- matrix(FALSE, 10,10); expected[6,6] <- TRUE
  expect_identical(as.matrix(at_mask(p)), expected)
  extracted <- at_extract(p)
  expect_equal(nrow(extracted), 1L)
  # R column-major fixture: row 6, column 6 is 56.
  if (nrow(extracted)) expect_equal(extracted$value, 56)
})

test_that("A16 mixed-level set operations reject missing image scale context", {
  a <- at_roi_rect(0,0,10,10,"a")
  b <- at_roi_rect(0,0,5,5,"a",level = 1L)
  # Bare ROIs do not establish that a level is isotropic or a power of two.
  expect_error(at_roi_difference(a,b), "[Ll]evel|[Ss]cale|[Ii]mage|[Cc]oordinate")
})

test_that("A18 downsampled overlay retains level-zero image extent", {
  img <- new_annot_image("audit-display", "raster", c(2048L,8L), 1L,
    list(c(2048L,8L)), 1L, handle = list(data = array(0, c(8,2048,1))))
  p <- at_project(img, at_layer_add(at_layer("L"), at_roi_rect(1800,2,1900,6,"a")))
  .tile_cache_clear()
  withr::defer(.tile_cache_clear())
  plot <- at_plot_overlay(p)
  # Inspect rendered raster bounds, allowing any internal representation.
  raster <- ggplot2::ggplot_build(plot)$data[[1]]
  expect_equal(range(c(raster$xmin, raster$xmax)), c(0,2048))
  expect_equal(range(c(raster$ymin, raster$ymax)), c(-8,0))
})

test_that("A21 per-ROI export uses both anisotropic image scale factors", {
  skip_if_not_installed("tiff")
  img <- new_annot_image("audit-pyramid", "tiff", c(100L,80L), 2L,
                        list(c(100L,80L),c(25L,40L)), 1L)
  p <- at_project(img, at_layer_add(at_layer("L"), at_roi_rect(2,2,5,5,"a",level=1L)))
  dir <- tempfile(); withr::defer(unlink(dir, recursive=TRUE))
  rc <- at_write_masks(p, dir, per="roi", type="binary")
  # x: [8,20), y: [4,10); 12 * 6 = 72 pixels.
  expected <- matrix(0L,80,100); expected[5:10,9:20] <- 1L
  expect_equal(rc$n_px, 72L)
  expect_equal(as.matrix(at_mask(p)) * 1L, expected)
  expect_true(all(tiff::readTIFF(rc$path, as.is=TRUE) == expected))
})
