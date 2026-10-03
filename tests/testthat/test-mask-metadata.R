# These expectations use tiny, manually enumerable arrays; no rasteriser oracle.
metadata_pair <- function(overlap = "bitor", values = c(a = 1L, b = 2L, absent = 4L)) {
  l <- at_layer_add(at_layer("L"), at_roi_rect(0, 0, 2, 1, label = "a"))
  l <- at_layer_add(l, at_roi_rect(1, 0, 3, 1, label = "b"))
  at_mask(l, "multiclass", values = values, overlap = overlap, dims = c(3, 2))
}

test_that("versioned metadata preserves encoding and the global codebook", {
  m <- metadata_pair()
  expect_identical(as.matrix(m), matrix(c(1L, 3L, 2L, 0L, 0L, 0L), 2, byrow = TRUE))
  md <- attr(m, "mask_metadata")
  expect_identical(md$schema_version, 1L)
  expect_identical(md$encoding, "bitfield")
  expect_identical(md$background, 0L)
  expect_identical(md$grid$dims, c(3L, 2L))
  expect_identical(at_mask_legend(m)$label, c("a", "b", "absent"))
  expect_identical(at_mask_legend(m)$n_px, c(2L, 2L, 0L))
  expect_identical(at_mask_stats(m)$n_px, c(2L, 2L, 0L))
  cat <- metadata_pair("last", c(a = 3L, b = 2L, absent = 4L))
  expect_identical(attr(cat, "mask_metadata")$encoding, "categorical")
  expect_identical(at_mask_stats(cat)$n_px, c(1L, 2L, 0L))
})

test_that("invalid codes fail before rasterisation and binary background is effective zero", {
  r <- at_roi_rect(0, 0, 1, 1, label = "a")
  expect_error(at_mask(r, "multiclass", values = c(a = 0L)), "background")
  expect_error(at_mask(r, "multiclass", values = c(a = 1L, b = 1L)), "unique|duplicate")
  expect_error(at_mask(r, "multiclass", values = c(a = 3L), overlap = "bitor"), "single.bit|power")
  expect_error(at_mask(r, "multiclass", values = c(a = 1L), overlap = "bitor", background = 4L), "background")
  expect_error(at_mask(r, background = 1L), "background")
  expect_error(at_mask(at_layer("empty"), background = 1L), "background")
  m <- at_mask(r, background = 9L, dims = c(2, 1))
  expect_identical(as.matrix(m), matrix(c(TRUE, FALSE), 1))
  expect_identical(attr(m, "mask_metadata")$background, 0L)
})

test_that("empty masks retain typed metadata and mapped absent labels through NPY", {
  m <- at_mask(at_layer("empty"), "multiclass", dims = c(3, 2), values = c(a = 3L))
  expect_identical(at_mask_legend(m)$label, "a")
  expect_identical(at_mask_stats(m)$n_px, 0L)
  for (mask in list(m, at_mask(at_layer("empty"), "multiclass", dims = c(3, 2)))) {
    p <- tempfile(fileext = ".npy")
    at_write_npy(mask, p)
    recovered <- at_read_npy(p)
    expect_identical(at_mask_legend(recovered), at_mask_legend(mask))
    expect_identical(attr(recovered, "mask_metadata"), attr(mask, "mask_metadata"))
  }
})

test_that("RDS embedded labels precede sidecars and explicit overrides precede embedded metadata", {
  m <- metadata_pair()
  p <- tempfile(fileext = ".rds")
  saveRDS(m, p)
  jsonlite::write_json(list(level = 2, legend = data.frame(value = 1, label = "wrong")), paste0(p, ".legend.json"))
  l <- at_read_mask(p)
  expect_setequal(vapply(l$rois, `[[`, character(1), "label"), c("a", "b"))
  override <- data.frame(value = c(1L, 2L, 4L), label = c("A", "B", "Absent"))
  l <- at_read_mask(p, level = 1L, legend = override)
  expect_setequal(vapply(l$rois, `[[`, character(1), "label"), c("A", "B"))
  expect_true(all(vapply(l$rois, `[[`, integer(1), "level") == 1L))
})

test_that("NPY storage orientation is distinct from the logical grid", {
  m <- metadata_pair()
  p <- tempfile(fileext = ".npy")
  at_write_npy(m, p, transpose = TRUE)
  expect_identical(as.matrix(at_read_npy(p, transpose = TRUE)), as.matrix(m))
  expect_error(at_read_npy(p), "transpose|orientation")
})

test_that("corrupt dimensions and schemas cannot validate themselves", {
  m <- metadata_pair()
  attr(m, "dims") <- c(9L, 8L)
  p <- tempfile(fileext = ".rds")
  saveRDS(m, p)
  expect_error(at_read_mask(p), "dimension|grid")
  m <- metadata_pair()
  attr(m, "mask_metadata")$schema_version <- 99L
  saveRDS(m, p)
  expect_error(at_read_mask(p), "schema")
  p <- tempfile(fileext = ".npy")
  at_write_npy(metadata_pair(), p)
  writeLines('{"legend": {"broken": 1}}', paste0(p, ".legend.json"))
  expect_error(at_read_npy(p), "legend")
})

test_that("preview counts and display include composite membership", {
  m <- metadata_pair()
  pv <- at_mask_preview(m, max_dim = 2L)
  expect_identical(at_mask_legend(pv)$n_px, c(1L, 1L, 0L))
  expect_identical(attr(pv, "mask_metadata")$grid$dims, c(2L, 1L))
  expect_identical(attr(pv, "mask_metadata")$grid$stride, c(2, 2))
  expect_false(anyNA(plot(m)$data$label))
  expect_true("a + b" %in% plot(m)$data$label)
})

test_that("derive uses declared membership/background and rejects incompatible declared grids", {
  anatomy <- metadata_pair()
  state <- metadata_pair("last", c(a = 5L, b = 6L, absent = 7L))
  d <- at_mask_derive(state, anatomy, keep_label = "a", alignment = "assert")
  expect_identical(as.matrix(d), matrix(c(5L, 6L, 0L, 0L, 0L, 0L), 2, byrow = TRUE))
  expect_identical(at_mask_legend(d)$n_px, c(1L, 1L, 0L))
  attr(anatomy, "level") <- 1L
  attr(anatomy, "mask_metadata")$grid$level <- 1L
  expect_error(at_mask_derive(state, anatomy, keep_label = "a"), "grid|level")
})

test_that("signed categorical imports retain samples and conservative legacy semantics", {
  p <- tempfile(fileext = ".npy")
  .npy_write_matrix(matrix(c(-3L, 0L, 3L), 1), p)
  m <- at_read_npy(p)
  expect_identical(as.matrix(m), matrix(c(-3L, 0L, 3L), 1))
  expect_identical(attr(m, "mask_metadata")$encoding, "instance")
  expect_identical(attr(m, "mask_metadata")$status, "legacy-default")
  expect_identical(at_mask_stats(m)$n_px, c(1L, 1L))
})

metadata_source_mask <- function(entry = "entry-a", generation = "read-a", path = "/source/image.tif") {
  img <- tiny_image()
  img$source_descriptor <- list(schema_version = 1L, path = path, backend = "raster",
                               options = list(), signature = list(size = 123, mtime = 1))
  img$read_generation <- generation
  img$cache_identity <- generation
  p <- at_project(img, at_layer_add(at_layer("L"), at_roi_rect(0, 0, 2, 2, "a")))
  p$meta$entry_id <- entry
  at_mask(p, "multiclass")
}

test_that("alignment compares durable descriptors, preserving separate entry provenance", {
  a <- metadata_source_mask()
  b <- metadata_source_mask("entry-b", "read-b")
  expect_identical(attr(a, "mask_metadata")$source$entry_id, "entry-a")
  expect_null(attr(a, "mask_metadata")$source$read_generation)
  d <- at_mask_derive(a, b, keep_label = "a")
  expect_identical(attr(d, "mask_metadata")$derivation$anatomy_alignment, "verified")
  b <- metadata_source_mask(path = "/other/image.tif")
  expect_error(at_mask_derive(a, b, keep_label = "a"), "source")
  expect_identical(attr(at_mask_derive(a, b, keep_label = "a", alignment = "assert"), "mask_metadata")$derivation$anatomy_alignment, "asserted")
  a <- metadata_pair(); b <- metadata_pair("last")
  expect_error(at_mask_derive(a, b, keep_label = "a"), "provenance|assert")
})

test_that("background-aware derivation and explicit legacy overrides preserve meaning", {
  p <- tempfile(fileext = ".npy")
  .npy_write_matrix(matrix(c(5L, 5L, 9L), 1), p)
  state <- at_read_npy(p, legend = data.frame(value = 5L, label = "state"),
                       metadata = list(background = 9L, encoding = "categorical"))
  .npy_write_matrix(matrix(c(1L, 3L, 2L), 1), p)
  anatomy <- at_read_npy(p, legend = data.frame(value = c(1L, 2L), label = c("a", "b")),
                         metadata = list(encoding = "bitfield", overlap = "bitor"))
  .npy_write_matrix(matrix(c(8L, 2L, 8L), 1), p)
  artefact <- at_read_npy(p, legend = data.frame(value = 2L, label = "bad"),
                          metadata = list(background = 8L, encoding = "categorical"))
  d <- at_mask_derive(state, anatomy, artefact, keep_label = "a", alignment = "assert")
  expect_identical(as.matrix(d), matrix(c(5L, 9L, 9L), 1))
  expect_identical(attr(d, "mask_metadata")$background, 9L)
  expect_identical(at_mask_stats(d)$n_px, 1L)
})

test_that("legacy RDS metadata can be explicitly disambiguated without guessing bitfields", {
  m <- metadata_pair()
  attr(m, "mask_metadata") <- NULL
  p <- tempfile(fileext = ".rds"); saveRDS(m, p)
  expect_error(at_read_mask(p), "codebook|encoding")
  l <- at_read_mask(p, metadata = list(encoding = "bitfield", overlap = "bitor"))
  expect_setequal(vapply(l$rois, `[[`, character(1), "label"), c("a", "b"))
})

test_that("malformed versioned source/grid/legend and fractional samples fail explicitly", {
  for (mutate in list(
    function(md) { md$source <- "bad"; md },
    function(md) { md$grid$level <- 0.5; md },
    function(md) { md$grid$dims <- c(3, 9); md },
    function(md) { md$schema_version <- "future"; md },
    function(md) { md$codebook <- list(broken = 1); md })) {
    m <- metadata_pair(); attr(m, "mask_metadata") <- mutate(attr(m, "mask_metadata"))
    p <- tempfile(fileext = ".rds"); saveRDS(m, p)
    expect_error(at_read_mask(p), "metadata|schema|source|grid|Grid|dimension|legend")
  }
  p <- tempfile(fileext = ".rds")
  saveRDS(matrix(c(0, 1.5), 1), p)
  expect_error(at_read_mask(p), "integer")
})

test_that("legacy alignment assumptions remain visible", {
  p <- tempfile(fileext = ".npy")
  .npy_write_matrix(matrix(c(1L, 0L), 1), p)
  a <- at_read_npy(p)
  .npy_write_matrix(matrix(c(1L, 1L), 1), p)
  b <- at_read_npy(p)
  d <- at_mask_derive(a, b, keep_label = "1")
  expect_identical(attr(d, "mask_metadata")$derivation$anatomy_alignment, "legacy-assumed")
  expect_identical(attr(d, "mask_metadata")$status, "legacy-default")
})

test_that("TIFF mask samples are validated before coercion or plane selection", {
  skip_if_not_installed("tiff")
  p <- tempfile(fileext = ".tif"); file.create(p)
  testthat::local_mocked_bindings(.tiff_raw_read = function(...) list(matrix(c(0, 1.5), 1)))
  expect_error(at_read_mask(p), "integer|fraction")
  testthat::local_mocked_bindings(.tiff_raw_read = function(...) list(array(1L, c(2, 3, 2))))
  expect_error(at_read_mask(p), "plane|dimension|2-D")
})

test_that("NPY polygonisation validates storage orientation metadata", {
  p <- tempfile(fileext = ".npy")
  at_write_npy(metadata_pair(), p, transpose = TRUE)
  l <- at_read_mask(p)
  expect_setequal(vapply(l$rois, `[[`, character(1), "label"), c("a", "b"))
  j <- jsonlite::read_json(paste0(p, ".legend.json"), simplifyVector = TRUE)
  j$storage$shape <- c(30, 20)
  jsonlite::write_json(j, paste0(p, ".legend.json"), auto_unbox = TRUE, null = "null")
  expect_error(at_read_mask(p), "storage|shape")
})

test_that("sidecars retain source options and signatures at full precision", {
  m <- metadata_source_mask()
  attr(m, "mask_metadata")$source$descriptor$options <- list(scale = 1 / 7)
  attr(m, "mask_metadata")$source$descriptor$signature$mtime <- 12345.6789012345
  p <- tempfile(fileext = ".npy"); at_write_npy(m, p)
  back <- at_read_npy(p)
  expect_equal(attr(back, "mask_metadata")$source, attr(m, "mask_metadata")$source, tolerance = 1e-14)
  expect_no_error(at_mask_derive(m, back, keep_label = "a"))
})

test_that("sampled preview grids cannot be imported as unscaled editable ROIs", {
  m <- at_mask_preview(metadata_pair(), max_dim = 2L)
  for (ext in c("rds", "npy")) {
    p <- tempfile(fileext = paste0(".", ext))
    if (ext == "rds") saveRDS(m, p) else at_write_npy(m, p)
    expect_error(at_read_mask(p), "sampled|stride|original.resolution")
  }
})

test_that("printing validates dimensions and refreshes membership counts", {
  m <- metadata_pair()
  m[1, 1] <- 0L
  output <- paste(capture.output(print(m)), collapse = "\n")
  expect_match(output, "a\\s+L\\s+<NA>\\s+1\\s+")
  attr(m, "dims") <- c(8L, 9L)
  expect_error(print(m), "dimension")
})

test_that("source alignment preserves literal option names, shapes, nesting and types", {
  m <- metadata_source_mask()
  option_pairs <- list(
    list(list(mapping = c(red = 1L, green = 2L)), list(mapping = c(green = 1L, red = 2L))),
    list(list(shape = matrix(1:6, 2, 3)), list(shape = matrix(1:6, 3, 2))),
    list(list(mapping = list(1L, 2L)), list(mapping = c(1L, 2L))),
    list(list(mapping = c(1L, 2L)), list(mapping = c(1, 2)))
  )
  for (pair in option_pairs) {
    attr(m, "mask_metadata")$source$descriptor$options <- pair[[1]]
    n <- m
    attr(n, "mask_metadata")$source$descriptor$options <- pair[[2]]
    expect_error(at_mask_derive(m, n, keep_label = "a"), "source.*conflict")
    expect_identical(attr(at_mask_derive(m, n, keep_label = "a", alignment = "assert"), "mask_metadata")$derivation$anatomy_alignment, "asserted")
  }
})

test_that("structured source options survive NPY and TIFF sidecars exactly", {
  options <- list(mapping = c(red = 1L, green = 2L),
                  shape = matrix(as.double(1:6), 2, dimnames = list(c("r", "g"), c("a", "b", "c"))),
                  nested = list(list(1L, 2L), list(a = NULL, b = list(integer(), double(), logical(), character()))),
                  types = list(TRUE, 1L, 1, 1 / 7, 1 + 2i, as.raw(c(0, 255))),
                  missing = list(c(NA_real_, NaN, Inf, -Inf), NA_integer_, NA_character_, NA),
                  attributed = structure(c(1, 2), unit = "nm"))
  m <- metadata_source_mask()
  attr(m, "mask_metadata")$source$descriptor$options <- options
  for (ext in c("npy", "tif")) {
    p <- tempfile(fileext = paste0(".", ext))
    if (ext == "npy") at_write_npy(m, p) else .write_legend_json(m, paste0(p, ".legend.json"))
    recovered <- .mask_read_sidecar(p)$mask_metadata$source$descriptor$options
    expect_identical(recovered, options)
    if (ext == "npy") {
      back <- at_read_npy(p)
      expect_identical(attr(back, "mask_metadata")$source$descriptor$options, options)
      expect_identical(attr(at_mask_derive(m, back, keep_label = "a"), "mask_metadata")$derivation$anatomy_alignment, "verified")
    }
  }
})

test_that("malformed or unknown source option encodings fail explicitly", {
  for (encoding in c("typed-json-v1", "typed-json-v999")) {
    m <- metadata_source_mask()
    p <- tempfile(fileext = ".npy"); at_write_npy(m, p)
    j <- jsonlite::read_json(paste0(p, ".legend.json"), simplifyVector = FALSE)
    j$mask_metadata$source$descriptor$options_encoding <- encoding
    j$mask_metadata$source$descriptor$options <- list(schema_version = 1L, node = list(type = "mystery"))
    jsonlite::write_json(j, paste0(p, ".legend.json"), auto_unbox = TRUE, null = "null")
    expect_error(at_read_npy(p), "option.*encod|encod.*option")
  }
})

test_that("legacy option JSON remains unverified after import and re-export", {
  m <- metadata_source_mask()
  p <- tempfile(fileext = ".npy"); at_write_npy(m, p)
  j <- jsonlite::read_json(paste0(p, ".legend.json"), simplifyVector = FALSE)
  j$mask_metadata$source$descriptor$options_encoding <- NULL
  j$mask_metadata$source$descriptor$options <- list(mapping = c(1L, 2L))
  jsonlite::write_json(j, paste0(p, ".legend.json"), auto_unbox = TRUE, null = "null")
  old <- at_read_npy(p)
  expect_identical(attr(old, "mask_metadata")$source$options_status, "legacy-json")
  expect_error(at_mask_derive(m, old, keep_label = "a"), "unverified|assertion")
  q <- tempfile(fileext = ".npy"); at_write_npy(old, q)
  back <- at_read_npy(q)
  expect_identical(attr(back, "mask_metadata")$source$options_status, "legacy-json")
  expect_error(at_mask_derive(m, back, keep_label = "a"), "unverified|assertion")
})

test_that("typed options reject future versions and malformed shape attributes", {
  scalar <- function(type, data) list(type = type, data = data, attributes = NULL)
  wrong_shape <- scalar("integer", as.list(as.character(1:4)))
  wrong_shape$attributes <- list(list(name = "dim", value = scalar("double", list("2.5", "2"))))
  for (encoded in list(
      list(schema_version = 99L, node = scalar("list", list())),
      list(schema_version = 1L, node = scalar("list", list(wrong_shape))))) {
    p <- tempfile(fileext = ".npy"); at_write_npy(metadata_source_mask(), p)
    j <- jsonlite::read_json(paste0(p, ".legend.json"), simplifyVector = FALSE)
    j$mask_metadata$source$descriptor$options <- encoded
    jsonlite::write_json(j, paste0(p, ".legend.json"), auto_unbox = TRUE, null = "null")
    expect_error(at_read_npy(p), "source option encoding")
  }
})

test_that("accepted atomic S4 source options retain formal identity through sidecars", {
  methods::setClass("t06_sidecar_num_round2", contains = "numeric", where = .GlobalEnv)
  withr::defer(methods::removeClass("t06_sidecar_num_round2", where = .GlobalEnv))
  options <- list(calibration = methods::new("t06_sidecar_num_round2", 1:2))
  expect_true(.serializable_options(options))
  expect_true(isS4(options$calibration))
  m <- metadata_source_mask()
  attr(m, "mask_metadata")$source$descriptor$options <- options
  p <- tempfile(fileext = ".npy"); at_write_npy(m, p)
  back <- at_read_npy(p)
  recovered <- attr(back, "mask_metadata")$source$descriptor$options
  expect_true(isS4(recovered$calibration))
  expect_identical(recovered, options)
  expect_no_error(at_mask_derive(m, back, keep_label = "a"))
  # Embedded RDS remains exact and authoritative over an unrelated sidecar.
  p <- tempfile(fileext = ".rds"); saveRDS(m, p)
  layer <- at_read_mask(p)
  expect_identical(layer$meta$mask_metadata$source$descriptor$options, options)
})

test_that("inferred reader options cannot establish verified source alignment", {
  a <- metadata_source_mask("entry-a")
  b <- metadata_source_mask("entry-b")
  attr(a, "mask_metadata")$source$descriptor$options_inferred <- TRUE
  attr(b, "mask_metadata")$source$descriptor$options_inferred <- TRUE
  expect_error(at_mask_derive(a, b, keep_label = "a"), "inferred|unverified")
  expect_identical(attr(at_mask_derive(a, b, keep_label = "a", alignment = "assert"), "mask_metadata")$derivation$anatomy_alignment, "asserted")
  p <- tempfile(fileext = ".npy"); at_write_npy(b, p)
  back <- at_read_npy(p)
  expect_true(attr(back, "mask_metadata")$source$descriptor$options_inferred)
  expect_error(at_mask_derive(a, back, keep_label = "a"), "inferred|unverified")
  attr(a, "mask_metadata")$source$descriptor$options_inferred <- FALSE
  expect_error(at_mask_derive(a, back, keep_label = "a"), "inferred|unverified")
  expect_error(at_mask_derive(back, a, keep_label = "a"), "inferred|unverified")
})

test_that("source descriptors reject malformed supplied inference flags", {
  for (flag in list(NA, 1L, "TRUE", logical(), c(TRUE, FALSE), NULL)) {
    m <- metadata_source_mask()
    descriptor <- attr(m, "mask_metadata")$source$descriptor
    descriptor["options_inferred"] <- list(flag)
    expect_error(.validate_descriptor(descriptor), "options_inferred")
    attr(m, "mask_metadata")$source$descriptor <- descriptor
    p <- tempfile(fileext = ".rds"); saveRDS(m, p)
    expect_error(at_read_mask(p), "options_inferred")
  }
})

test_that("formal flags survive without invoking class constructors or requiring definitions", {
  methods::setClass("t06_sidecar_slots_round2", contains = "numeric",
                    slots = c(unit = "character"), where = .GlobalEnv)
  options <- list(calibration = methods::new("t06_sidecar_slots_round2", c(1, 2), unit = "nm"))
  m <- metadata_source_mask()
  attr(m, "mask_metadata")$source$descriptor$options <- options
  p <- tempfile(fileext = ".npy"); at_write_npy(m, p)
  methods::removeClass("t06_sidecar_slots_round2", where = .GlobalEnv)
  back <- at_read_npy(p)
  recovered <- attr(back, "mask_metadata")$source$descriptor$options
  expect_true(isS4(recovered$calibration))
  expect_identical(recovered, options)
})

test_that("version-one typed options retain data but cannot prove formal identity", {
  m <- metadata_source_mask()
  p <- tempfile(fileext = ".npy"); at_write_npy(m, p)
  j <- jsonlite::read_json(paste0(p, ".legend.json"), simplifyVector = FALSE)
  j$mask_metadata$source$descriptor$options_encoding <- "typed-json-v1"
  j$mask_metadata$source$descriptor$options <- list(
    schema_version = 1L, node = list(type = "list", data = list(), attributes = NULL))
  jsonlite::write_json(j, paste0(p, ".legend.json"), auto_unbox = TRUE, null = "null")
  old <- at_read_npy(p)
  expect_identical(attr(old, "mask_metadata")$source$descriptor$options, list())
  expect_identical(attr(old, "mask_metadata")$source$options_status, "legacy-json")
  expect_error(at_mask_derive(m, old, keep_label = "a"), "unverified|assertion")
  q <- tempfile(fileext = ".npy"); at_write_npy(old, q)
  back <- at_read_npy(q)
  expect_identical(attr(back, "mask_metadata")$source$options_status, "legacy-json")
  expect_error(at_mask_derive(m, back, keep_label = "a"), "unverified|assertion")
})

test_that("typed formal flags and encoding markers must be explicit valid scalars", {
  for (flag in list(NA, 1L, "TRUE", logical(), c(TRUE, FALSE), NULL)) {
    p <- tempfile(fileext = ".npy"); at_write_npy(metadata_source_mask(), p)
    j <- jsonlite::read_json(paste0(p, ".legend.json"), simplifyVector = FALSE)
    j$mask_metadata$source$descriptor$options$node["s4"] <- list(flag)
    jsonlite::write_json(j, paste0(p, ".legend.json"), auto_unbox = TRUE, null = "null")
    expect_error(at_read_npy(p), "source option encoding")
  }
  for (encoding in list(1L, c("typed-json-v1", "typed-json-v2"), NULL)) {
    p <- tempfile(fileext = ".npy"); at_write_npy(metadata_source_mask(), p)
    j <- jsonlite::read_json(paste0(p, ".legend.json"), simplifyVector = FALSE)
    j$mask_metadata$source$descriptor["options_encoding"] <- list(encoding)
    jsonlite::write_json(j, paste0(p, ".legend.json"), auto_unbox = TRUE, null = "null")
    expect_error(at_read_npy(p), "source option encoding")
  }
})
