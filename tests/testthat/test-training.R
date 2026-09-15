skip_if_not_installed("tiff")

# A 40 x 30 image with known rectangles; masks are derived independently from
# pixel-centre membership of the rectangle bounds.
train_image <- function(name) {
  new_annot_image(source = paste0(name, ".tif"), backend = "raster", dims = c(40L, 30L),
                  n_levels = 1L, level_dims = list(c(40L, 30L)), n_bands = 3L,
                  handle = list(data = array(1, dim = c(30, 40, 3))))
}

train_session <- function(n = 4L) {
  s <- demo_session(n)
  for (i in seq_len(n)) {
    lyr <- at_layer("tissue", labels = c("tumour", "stroma"))
    lyr <- at_layer_add(lyr, at_roi_rect(2, 3, 12, 9, label = "tumour", id = sprintf("t-%d", i)))
    lyr <- at_layer_add(lyr, at_roi_rect(22, 2, 30, 18, label = "stroma", id = sprintf("s-%d", i)))
    s$projects[[i]] <- at_project(train_image(sprintf("img%d", i)), lyr, name = sprintf("img%d", i))
  }
  s
}

rect_membership <- function(xmin, ymin, xmax, ymax, w, h) {
  m <- matrix(FALSE, h, w)
  for (i in seq_len(h)) for (j in seq_len(w)) {
    m[i, j] <- (j - 0.5) >= xmin && (j - 0.5) < xmax && (i - 0.5) >= ymin && (i - 0.5) < ymax
  }
  m
}

test_that("grouped splits are deterministic, independent of RNG, and leak-free", {
  sess <- train_session(4)
  groups <- data.frame(entry_id = sprintf("entry-%04d", 1:4), sample_id = c("s1", "s1", "s2", "s3"))
  dest <- file.path(withr::local_tempdir(), "ds")
  ds <- at_training_export(sess, dest, tile_size = 10, group_by = "sample_id", groups = groups,
                           fractions = c(train = 0.34, validation = 0.33, test = 0.33), seed = 7)
  # Independent assignment: rank groups by sha256("7:<group>") and cut 3 groups into thirds.
  g <- c("s1", "s2", "s3")
  ranked <- g[order(vapply(g, function(x) unname(tools::sha256sum(bytes = charToRaw(paste0("7:", x)))),
                           character(1)), method = "radix")]
  expected <- stats::setNames(c("train", "validation", "test"), ranked)
  split_of <- vapply(ds$manifest$images, `[[`, character(1), "split")
  expect_identical(split_of, unname(expected[c("s1", "s1", "s2", "s3")]))
  expect_identical(ds$checks$status[ds$checks$check == "split_leakage"], "ok")
  set.seed(1); a <- .assign_splits(g, c(train = 1, test = 1), 3)
  set.seed(999); b <- .assign_splits(g, c(train = 1, test = 1), 3)
  expect_identical(a, b)
  err <- tryCatch(at_training_export(sess, file.path(withr::local_tempdir(), "x"),
                                     split = list(train = c("img1", "img2"), test = c("img2")),
                                     group_by = "image_id",
                                     groups = data.frame(entry_id = sprintf("entry-%04d", 1:4),
                                                         image_id = paste0("img", 1:4))),
                  error = function(e) e)
  expect_true(err$code %in% c("SPLIT_LEAKAGE", "GROUP_MISSING"))
})

test_that("tile grid, exclusions and mask values match independent arithmetic", {
  sess <- train_session(1)
  dest <- file.path(withr::local_tempdir(), "ds")
  ds <- at_training_export(sess, dest, tile_size = 16, overlap = 4, mask_type = "labelled",
                           label_map = c(tumour = 3L, stroma = 5L), fractions = c(train = 1))
  # Stride 12: x0 in 0, 12, 24, 36 (w = 40); y0 in 0, 12, 24 (h = 30). Full tiles need
  # x0 + 16 <= 40 and y0 + 16 <= 30: x0 in {0, 12, 24}, y0 in {0, 12}.
  tiles <- ds$manifest$tiles
  expect_identical(length(tiles), 4L * 3L)
  inc <- Filter(function(t) t$status == "included", tiles)
  expect_identical(length(inc), 6L)
  expect_identical(ds$manifest$counts$excluded$partial, 6L)
  full <- matrix(0L, 30, 40)
  full[rect_membership(2, 3, 12, 9, 40, 30)] <- 3L
  full[rect_membership(22, 2, 30, 18, 40, 30)] <- 5L
  for (t in inc) {
    m <- tiff::readTIFF(file.path(dest, t$mask_file), as.is = TRUE)
    expect_identical(matrix(as.integer(m), 16),
                     full[(t$y + 1):(t$y + 16), (t$x + 1):(t$x + 16)], label = t$tile_id)
  }
  expect_true(all(ds$checks$status == "ok"))
  lg <- ds$manifest$mask_encoding$class_legend
  expect_identical(vapply(lg, `[[`, integer(1), "code"), c(3L, 5L))
  expect_identical(ds$manifest$mask_encoding$annotatr_mask_type, "multiclass")
  # The 10 x 6 px tumour rectangle lies inside exactly one included tile.
  expect_equal(ds$manifest$counts$class_balance$train[["3"]], sum(full == 3L))
})

test_that("instance masks carry their own legend and images are written only on request", {
  sess <- train_session(1)
  dest <- file.path(withr::local_tempdir(), "ds")
  ds <- at_training_export(sess, dest, tile_size = 20, mask_type = "instance", include_images = TRUE,
                           bands = 2:3, fractions = c(train = 1))
  inst <- ds$manifest$images[[1]]$instance_legend
  expect_identical(vapply(inst, `[[`, character(1), "roi_id"), c("t-1", "s-1"))
  t1 <- Filter(function(t) t$status == "included", ds$manifest$tiles)[[1]]
  con <- file(file.path(dest, t1$image_file), "rb")
  magic <- readBin(con, "raw", 6)
  ver <- readBin(con, "raw", 2)
  hlen <- readBin(con, "integer", size = 2, signed = FALSE, endian = "little")
  header <- rawToChar(readBin(con, "raw", hlen))
  close(con)
  expect_identical(as.integer(magic[2:6]), as.integer(charToRaw("NUMPY")))
  expect_match(header, "'descr': '<f4'")
  expect_match(header, "'shape': \\(20, 20, 2\\)")
})

test_that("the dataset check detects tampered, out-of-range and leaking datasets", {
  sess <- train_session(2)
  dest <- file.path(withr::local_tempdir(), "ds")
  ds <- at_training_export(sess, dest, tile_size = 10, fractions = c(train = 0.5, test = 0.5))
  expect_true(all(at_training_check(dest, x = sess)$status == "ok"))
  t1 <- Filter(function(t) t$status == "included" && t$foreground_px > 0, ds$manifest$tiles)[[1]]
  m <- matrix(9L, 10, 10)
  tiff::writeTIFF(m / 255, file.path(dest, t1$mask_file), bits.per.sample = 8L)
  chk <- at_training_check(dest, x = sess)
  expect_identical(chk$status[chk$check == "integrity"], "fail")
  expect_identical(chk$status[chk$check == "label_range"], "fail")
  expect_identical(chk$status[chk$check == "source_agreement"], "fail")
  man <- jsonlite::read_json(file.path(dest, "training-manifest.json"))
  man$tiles[[1]]$split <- if (identical(man$tiles[[1]]$split, "train")) "test" else "train"
  jsonlite::write_json(man, file.path(dest, "training-manifest.json"), auto_unbox = TRUE,
                       null = "null", digits = NA)
  expect_identical(at_training_check(dest)$status[1:2], c("fail", "fail"))
})

test_that("predictions import as staged, provenance-tagged ROIs and never overwrite reviews", {
  sess <- train_session(1)
  proj <- sess$projects[[1]]
  pred <- matrix(0L, 30, 40)
  pred[5:10, 5:15] <- 2L
  pred[20:25, 30:38] <- 1L
  map <- c(tumour = 1L, stroma = 2L)
  model <- list(name = "unet", version = "1.2", sha256 = strrep("a", 64))
  st <- at_training_import(proj, pred, map, model = model)
  expect_s3_class(st, "at_staged_patch")
  expect_identical(st$summary$create, 2L)
  expect_identical(at_annotation_revision(proj), st$base_revision)
  new <- Filter(function(r) r$source == "dnn_prediction", st$proposed$layers$predictions$rois)
  expect_setequal(vapply(new, `[[`, character(1), "label"), c("tumour", "stroma"))
  expect_identical(new[[1]]$attributes$review_status, "unreviewed")
  expect_identical(new[[1]]$attributes$prediction$model_sha256, strrep("a", 64))
  expect_identical(attr(st, "prediction_digest"),
                   unname(tools::sha256sum(bytes = writeBin(as.integer(pred), raw(), size = 4L,
                                                            endian = "little"))))
  stroma <- Filter(function(r) r$label == "stroma", new)[[1]]
  expect_equal(at_roi_area(stroma), 6 * 11)

  expect_identical(tryCatch(at_training_import(proj, pred[1:10, ], map), error = function(e) e$code),
                   "MASK_DIMENSIONS")
  bad <- pred; bad[1, 1] <- 7L
  expect_identical(tryCatch(at_training_import(proj, bad, map), error = function(e) e$code),
                   "LABEL_OUT_OF_RANGE")
  frac <- pred + 0.5
  expect_identical(tryCatch(at_training_import(proj, frac, map), error = function(e) e$code),
                   "DTYPE_INVALID")
  conf <- matrix(0.9, 30, 40)
  conf[20:25, 30:38] <- 0.2
  low <- at_training_import(proj, pred, map, confidence = conf, min_confidence = 0.5)
  expect_identical(low$summary$create, 1L)

  reviewed <- at_add_layer(proj, at_layer("predictions", labels = names(map)))
  kept <- at_roi_rect(0, 0, 3, 3, label = "tumour", id = "human-1", review_status = "reviewed")
  reviewed <- at_add_roi(reviewed, "predictions", kept)
  rep <- at_training_import(reviewed, pred, map, replace = TRUE)
  expect_identical(rep$operations$op[rep$operations$roi_id == "human-1"], "conflict")
  expect_false(is.null(.find_roi(rep$proposed, "human-1")))
})
