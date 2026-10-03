analytical_fixture <- function(name) {
  test_path("fixtures", "analytical", name)
}

read_literal_matrix <- function(rows) {
  do.call(rbind, lapply(rows, function(row) as.numeric(unlist(row))))
}

test_that("analytical cube bytes and ROI oracle retain literal independent values", {
  expected <- jsonlite::read_json(
    analytical_fixture("analysis-expected.json"), simplifyVector = FALSE
  )
  payload <- readBin(analytical_fixture("cube.dat"), "numeric", n = 60L,
                     size = 4L, endian = "little")
  cube <- aperm(array(payload, dim = c(3L, 5L, 4L)), c(3L, 2L, 1L))

  expect_identical(dim(cube), c(4L, 5L, 3L))
  expect_equal(cube[, , 1L], matrix(c(
    NaN, 112, 113, 114, 115,
    121, 122, 123, 124, 125,
    131, 132, 133, 134, 135,
    141, 142, 143, 144, 145
  ), nrow = 4L, byrow = TRUE))
  expect_true(is.infinite(cube[2L, 3L, 2L]) && cube[2L, 3L, 2L] > 0)
  expect_true(is.infinite(cube[3L, 4L, 3L]) && cube[3L, 4L, 3L] < 0)
  expect_true(is.nan(cube[4L, 5L, 3L]))

  expect_identical(as.integer(unlist(expected$shape_yxb)), c(4L, 5L, 3L))
  expect_identical(read_literal_matrix(expected$bitfield), matrix(c(
    1, 1, 1, 0, 0,
    1, 1, 3, 2, 2,
    1, 1, 3, 2, 2,
    0, 0, 2, 2, 2
  ), nrow = 4L, byrow = TRUE))
  expect_identical(
    c(expected$n_foreground, expected$n_overlap, expected$n_background),
    c(16L, 2L, 4L)
  )
  expect_identical(
    c(expected$sampling_units$unique_selected_pixels,
      expected$sampling_units$selected_roi_memberships,
      expected$sampling_units$roi_count,
      expected$sampling_units$image_count),
    c(16L, 18L, 2L, 1L)
  )
  union_band1 <- expected$union_pixel_statistics[[1L]]
  expect_identical(
    c(union_band1$n_selected, union_band1$n_valid, union_band1$n_invalid),
    c(16L, 15L, 1L)
  )
  expect_equal(c(union_band1$sum, union_band1$mean), c(1937, 1937 / 15))

  rois <- jsonlite::read_json(
    analytical_fixture("analysis-rois.geojson"), simplifyVector = FALSE
  )
  expect_identical(vapply(rois$features, `[[`, "", "id"), c(
    "00000000-0000-0000-0000-00000000012a",
    "00000000-0000-0000-0000-00000000012b"
  ))
  expect_identical(
    vapply(rois$features, function(x) x$properties$label, ""), c("A", "B")
  )
  expect_identical(
    read_literal_matrix(rois$features[[1L]]$geometry$coordinates[[1L]]),
    matrix(c(0, 0, 3, 0, 3, 3, 0, 3, 0, 0), ncol = 2L, byrow = TRUE)
  )
})

test_that("agreement fixtures preserve exact class, remapping, and bitfield cases", {
  expected <- jsonlite::read_json(
    analytical_fixture("agreement-expected.json"), simplifyVector = FALSE
  )
  categorical_reference <- as.matrix(at_read_npy(
    analytical_fixture("categorical-reference.npy")
  ))
  categorical_prediction <- as.matrix(at_read_npy(
    analytical_fixture("categorical-prediction.npy")
  ))
  remapped_prediction <- as.matrix(at_read_npy(
    analytical_fixture("categorical-prediction-remapped.npy")
  ))
  bitfield_reference <- as.matrix(at_read_npy(
    analytical_fixture("bitfield-reference.npy")
  ))
  bitfield_prediction <- as.matrix(at_read_npy(
    analytical_fixture("bitfield-prediction.npy")
  ))

  expect_identical(categorical_reference, matrix(c(
    0L, 1L, 1L, 2L, 0L, 1L, 2L, 2L, 0L, 0L, 2L, 1L
  ), nrow = 3L, byrow = TRUE))
  expect_identical(categorical_prediction, matrix(c(
    0L, 1L, 2L, 2L, 0L, 1L, 2L, 0L, 1L, 0L, 2L, 1L
  ), nrow = 3L, byrow = TRUE))
  expect_identical(remapped_prediction, matrix(c(
    0L, 2L, 1L, 1L, 0L, 2L, 1L, 0L, 2L, 0L, 1L, 2L
  ), nrow = 3L, byrow = TRUE))
  expect_identical(bitfield_reference, matrix(c(
    0L, 1L, 3L, 2L, 1L, 3L, 0L, 2L, 0L, 0L, 2L, 1L
  ), nrow = 3L, byrow = TRUE))
  expect_identical(bitfield_prediction, matrix(c(
    0L, 1L, 1L, 2L, 3L, 3L, 0L, 0L, 0L, 2L, 2L, 1L
  ), nrow = 3L, byrow = TRUE))

  expect_identical(expected$categorical$confusion, list(
    list(3L, 1L, 0L), list(0L, 3L, 1L), list(1L, 0L, 3L)
  ))
  expect_identical(expected$categorical$accuracy$fraction, "3/4")
  expect_identical(expected$categorical$kappa$fraction, "5/8")
  expect_identical(expected$categorical$per_class[[1L]]$dice$fraction, "3/4")
  expect_identical(expected$categorical$per_class[[1L]]$iou$fraction, "3/5")
  expect_null(expected$categorical$per_class[[3L]]$dice)
  expect_null(expected$categorical$per_class[[3L]]$iou)
  expect_identical(expected$bitfield$per_class[[1L]]$dice$fraction, "1")
  expect_identical(expected$bitfield$per_class[[2L]]$dice$fraction, "3/5")
  expect_identical(expected$bitfield$per_class[[2L]]$iou$fraction, "3/7")
  expect_identical(expected$bitfield$exact_membership_set_agreement$fraction, "2/3")
  expect_null(expected$background_only$kappa)
})

test_that("anisotropic area oracle declares calibration level and non-unit product", {
  expected <- jsonlite::read_json(
    analytical_fixture("physical-area-expected.json"), simplifyVector = FALSE
  )
  roi <- jsonlite::read_json(
    analytical_fixture("physical-roi-level1.geojson"), simplifyVector = FALSE
  )$features[[1L]]

  expect_identical(expected$level_dimensions, list(list(10L, 8L), list(4L, 2L)))
  expect_identical(as.numeric(unlist(expected$level0_pixel_size_um)), c(0.5, 3))
  expect_identical(expected$calibration_declared_at_level, 0L)
  expect_identical(expected$stored_roi_level, 1L)
  expect_identical(
    c(expected$geometric_area_level1_px2,
      expected$geometric_area_level0_px2,
      expected$physical_area_um2),
    c(2L, 20L, 30L)
  )
  expect_identical(roi$properties$level, 1L)
  expect_identical(
    read_literal_matrix(roi$geometry$coordinates[[1L]]),
    matrix(c(0, 0, 2, 0, 2, 1, 0, 1, 0, 0), ncol = 2L, byrow = TRUE)
  )
})

test_that("analytical inventory is explicit and committed bytes pass integrity checks", {
  inventory <- jsonlite::read_json(
    analytical_fixture("optional-formats.json"), simplifyVector = FALSE
  )
  expect_identical(inventory$repository_license, "MIT + file LICENSE")
  expect_identical(inventory$contains_acquired_or_third_party_image_data, FALSE)
  expect_identical(
    vapply(inventory$optional_formats, function(x) x$format, ""),
    c("OME-TIFF", "SpecCube", "vendor/acquired whole-slide formats")
  )
  expect_identical(
    inventory$optional_formats[[3L]]$qualification,
    "unavailable; no support claim"
  )

  manifest <- readLines(analytical_fixture("MD5SUMS"))
  fields <- strsplit(manifest, "  ", fixed = TRUE)
  expected_hash <- vapply(fields, `[[`, "", 1L)
  names(expected_hash) <- vapply(fields, `[[`, "", 2L)
  actual_hash <- unname(tools::md5sum(analytical_fixture(names(expected_hash))))
  expect_identical(actual_hash, unname(expected_hash))
})
