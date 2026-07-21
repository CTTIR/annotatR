# Mask agreement metrics: to validate an annotatR mask against a ground-truth
# .npy (or a second annotator), we need per-class Dice/IoU and an overall
# accuracy / Cohen's kappa. The package had no mask-vs-mask comparator.

test_that("identical masks agree perfectly", {
  a <- matrix(c(0, 1, 1, 0, 1, 1, 2, 2, 0), 3, 3, byrow = TRUE)
  ag <- at_mask_agreement(a, a)
  expect_true(all(ag$dice == 1))
  expect_true(all(ag$iou == 1))
  expect_equal(attr(ag, "overall")$accuracy, 1)
  expect_equal(attr(ag, "overall")$kappa, 1)
})

test_that("per-class Dice and IoU match a hand-computed case", {
  truth <- matrix(0L, 4, 4); truth[1:2, 1:2] <- 1L
  pred <- matrix(0L, 4, 4); pred[1:2, 1:2] <- 1L; pred[1, 1] <- 0L; pred[3, 3] <- 1L
  ag <- at_mask_agreement(truth, pred)
  r1 <- ag[ag$value == 1L, ]
  expect_identical(r1$tp, 3L)
  expect_identical(r1$fp, 1L)
  expect_identical(r1$fn, 1L)
  expect_equal(r1$dice, 0.75)
  expect_equal(r1$iou, 0.6)
  expect_equal(attr(ag, "overall")$accuracy, 0.875)
})

test_that("agreement labels classes from the reference mask legend", {
  lyr <- at_layer("anatomy", labels = c("wound", "healthy"))
  lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 3, 3, label = "wound"))
  lyr <- at_layer_add(lyr, at_roi_rect(3, 3, 6, 6, label = "healthy"))
  m <- at_mask(lyr, type = "multiclass", values = c(wound = 1L, healthy = 2L),
               dims = c(6, 6))
  ag <- at_mask_agreement(m, m)
  expect_identical(ag$label[ag$value == 1L], "wound")
  expect_identical(ag$label[ag$value == 2L], "healthy")
})

test_that("agreement aborts on mismatched dimensions", {
  expect_error(
    at_mask_agreement(matrix(0L, 3, 3), matrix(0L, 3, 4)),
    "dimension"
  )
})
