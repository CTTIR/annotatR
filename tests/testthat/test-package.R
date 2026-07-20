test_that("annotatR is installed with the expected version", {
  expect_identical(
    as.character(utils::packageVersion("annotatR")),
    "0.0.1"
  )
})

test_that("package namespace can be loaded", {
  expect_true(requireNamespace("annotatR", quietly = TRUE))
})
