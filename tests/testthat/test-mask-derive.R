# The derived training mask is the core cross-layer operation of the HSI scheme:
#   training = state WHERE anatomy == wound AND artefact == 0 AND state != unlabeled
# It has no home in the ROI-level set-ops, so at_mask_derive() combines the
# rasterised layer masks elementwise.

mk_mask <- function(rois, values, overlap = "last", dims = c(5, 5)) {
  lyr <- at_layer("L")
  for (r in rois) lyr <- at_layer_add(lyr, r)
  at_mask(lyr, type = "multiclass", values = values, overlap = overlap, dims = dims)
}

anatomy_m <- function() mk_mask(list(at_roi_rect(0, 0, 3, 5, label = "wound")),
                                c(wound = 1L))
state_m <- function() mk_mask(list(at_roi_rect(0, 0, 3, 2, label = "injury")),
                              c(injury = 2L))
artefact_m <- function() mk_mask(list(at_roi_rect(0, 0, 1, 1, label = "blood")),
                                 c(blood = 2L), overlap = "bitor")

test_that("derive keeps state only inside wound, artefact-free, and labelled", {
  d <- at_mask_derive(state_m(), anatomy_m(), artefact_m(), keep_label = "wound")
  dm <- as.matrix(d) # [y, x]
  expect_identical(dm[1, 1], 0L) # excluded by blood artefact
  expect_identical(dm[1, 2], 2L) # kept
  expect_identical(dm[2, 1], 2L)
  expect_identical(dm[2, 3], 2L)
  expect_identical(dm[3, 1], 0L) # state unlabeled (y = 3 outside the state rect)
  expect_identical(dm[1, 4], 0L) # outside the wound anatomy
  expect_identical(sum(dm == 2L), 5L) # 6 state pixels minus 1 blood pixel
})

test_that("derive without an artefact layer keeps all labelled wound pixels", {
  d <- at_mask_derive(state_m(), anatomy_m(), keep_label = "wound")
  dm <- as.matrix(d)
  expect_identical(dm[1, 1], 2L) # no artefact exclusion now
  expect_identical(sum(dm == 2L), 6L)
})

test_that("derive carries the state legend for surviving classes", {
  d <- at_mask_derive(state_m(), anatomy_m(), keep_label = "wound")
  lg <- at_mask_legend(d)
  expect_identical(lg$label[lg$value == 2L], "injury")
  expect_identical(lg$n_px[lg$value == 2L], 6L)
})

test_that("derive aborts on a missing keep label", {
  expect_error(
    at_mask_derive(state_m(), anatomy_m(), keep_label = "nonexistent"),
    "nonexistent"
  )
})

test_that("derive aborts on mismatched mask dimensions", {
  small <- mk_mask(list(at_roi_rect(0, 0, 2, 2, label = "wound")),
                   c(wound = 1L), dims = c(4, 4))
  expect_error(at_mask_derive(state_m(), small, keep_label = "wound"), "dimension")
})
