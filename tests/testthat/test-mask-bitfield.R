# The artefact layer of the HSI annotation scheme is a bitfield: a pixel may be
# several artefacts at once (specular = 1, blood = 2, shadow = 4, ...). This
# needs (a) explicit power-of-two class codes and (b) a bitwise-OR overlap
# policy so co-occurring artefacts combine rather than overwrite.

art_layer <- function() {
  lyr <- at_layer("artefact", labels = c("specular", "blood"))
  lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 6, 6, label = "specular"))
  lyr <- at_layer_add(lyr, at_roi_rect(4, 4, 10, 10, label = "blood"))
  lyr
}

test_that("an explicit values map assigns stable class codes, not match() order", {
  m <- at_mask(art_layer(), type = "multiclass",
               values = c(specular = 1L, blood = 2L, shadow = 4L),
               overlap = "last", dims = c(10, 10))
  lg <- at_mask_legend(m)
  expect_identical(lg$value[lg$label == "specular"], 1L)
  expect_identical(lg$value[lg$label == "blood"], 2L)
})

test_that("bitor overlap OR-combines overlapping artefact codes", {
  m <- at_mask(art_layer(), type = "multiclass",
               values = c(specular = 1L, blood = 2L),
               overlap = "bitor", dims = c(10, 10))
  mm <- as.matrix(m) # [y, x]
  expect_identical(mm[1, 1], 1L)   # specular only
  expect_identical(mm[10, 10], 2L) # blood only
  expect_identical(mm[5, 5], 3L)   # specular | blood
  expect_identical(mm[6, 6], 3L)
})

test_that("bitor legend enumerates base bit codes counted by bitwAnd", {
  m <- at_mask(art_layer(), type = "multiclass",
               values = c(specular = 1L, blood = 2L),
               overlap = "bitor", dims = c(10, 10))
  lg <- at_mask_legend(m)
  expect_setequal(lg$value, c(1L, 2L))
  # Every specular/blood pixel (including the composite 3s) is counted for its bit.
  expect_identical(lg$n_px[lg$value == 1L], 36L)
  expect_identical(lg$n_px[lg$value == 2L], 36L)
})

test_that("a values map missing a present label aborts", {
  expect_error(
    at_mask(art_layer(), type = "multiclass", values = c(specular = 1L),
            overlap = "bitor", dims = c(10, 10)),
    "blood"
  )
})

test_that("values map is rejected for non-multiclass masks", {
  expect_error(
    at_mask(art_layer(), type = "labelled", values = c(specular = 1L, blood = 2L),
            dims = c(10, 10)),
    "multiclass"
  )
})

test_that("default multiclass masking is unchanged when no values map is given", {
  m <- at_mask(art_layer(), type = "multiclass", dims = c(10, 10))
  lg <- at_mask_legend(m)
  # match()-order codes: specular seen first -> 1, blood -> 2.
  expect_identical(sort(lg$value), c(1L, 2L))
})
