# The guideline's core rule: a state/class ROI is painted ONLY inside its
# container region (e.g. state inside anatomy 'wound'). A layer declares this via
# at_layer(..., within = list(layer = , label = )); at_check_containment()
# reports ROIs that fall outside, mirroring at_check_geometry()'s report shape.

proj_state <- function(state_roi, within = list(layer = "anatomy", label = "wound"),
                       container_roi = at_roi_rect(2, 2, 8, 8, label = "wound")) {
  anatomy <- at_layer("anatomy", labels = "wound")
  anatomy <- at_layer_add(anatomy, container_roi)
  state <- do.call(at_layer, c(list("state", labels = "injury"),
                               if (!is.null(within)) list(within = within)))
  state <- at_layer_add(state, state_roi)
  at_project(tiny_image(), list(anatomy, state))
}

test_that("a contained ROI produces no containment issues", {
  rep <- at_check_containment(proj_state(at_roi_rect(3, 3, 7, 7, label = "injury")))
  expect_s3_class(rep, "tbl_df")
  expect_identical(nrow(rep), 0L)
})

test_that("a state ROI reaching outside the wound is reported", {
  rep <- at_check_containment(proj_state(at_roi_rect(0, 0, 4, 4, label = "injury")))
  expect_identical(nrow(rep), 1L)
  expect_identical(rep$layer, "state")
  expect_identical(rep$severity, "warning")
})

test_that("layers without a within constraint are ignored", {
  rep <- at_check_containment(proj_state(at_roi_rect(0, 0, 4, 4, label = "injury"),
                                         within = NULL))
  expect_identical(nrow(rep), 0L)
})

test_that("a missing container layer is an error-severity issue", {
  rep <- at_check_containment(
    proj_state(at_roi_rect(3, 3, 7, 7, label = "injury"),
               within = list(layer = "nonexistent"))
  )
  expect_identical(nrow(rep), 1L)
  expect_identical(rep$severity, "error")
  expect_match(rep$issue, "nonexistent")
})

test_that("tol tolerates sub-pixel overhang", {
  roi <- at_roi_rect(1.5, 1.5, 7, 7, label = "injury") # overhangs wound by 0.5
  expect_identical(nrow(at_check_containment(proj_state(roi))), 1L)
  expect_identical(nrow(at_check_containment(proj_state(roi), tol = 1)), 0L)
})
