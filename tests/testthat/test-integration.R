# End-to-end integration scenarios exercising the full pipeline.

test_that("Scenario A: spatial biology (multiplex -> layers -> mask -> QuPath)", {
  skip_if_not_installed("tiff")
  img <- at_example_image("multiplex")
  proj <- at_project(img, name = "A")
  tissue <- at_layer_add(at_layer("tissue", labels = "tissue"),
                         at_roi_rect(20, 20, 200, 200, label = "tissue"))
  tumour <- at_layer_add(at_layer("tumour", labels = "tumour", style = at_style(z = 2L)),
                         at_roi_circle(350, 150, 40, label = "tumour"))
  necrosis <- at_layer_add(at_layer("necrosis", labels = "necrosis"),
                           at_roi_rect(300, 350, 460, 470, label = "necrosis"))
  proj <- proj |>
    at_add_layer(tissue) |>
    at_add_layer(tumour) |>
    at_add_layer(necrosis)

  expect_s3_class(at_validate(proj), "annot_project")

  m <- at_mask(proj, "labelled", level = 0)
  dir <- withr::local_tempdir()
  p <- file.path(dir, "mask.tif")
  at_write_mask(m, p)
  expect_true(file.exists(paste0(p, ".legend.json")))

  # Read the mask back; recover three regions and the labels.
  lyr <- at_read_mask(p)
  expect_equal(at_layer_n(lyr), 3L)
  expect_setequal(unique(vapply(lyr$rois, `[[`, character(1), "label")),
                  c("tissue", "tumour", "necrosis"))

  # QuPath round-trip preserves classification names and yields valid colours.
  q <- file.path(dir, "q.geojson")
  at_write_qupath(proj, q)
  ql <- at_read_qupath(q)
  expect_setequal(unique(vapply(ql$rois, `[[`, character(1), "label")),
                  c("tissue", "tumour", "necrosis"))
  expect_true(all(grepl("^#[0-9A-Fa-f]{6}$", ql$style$colour)))
})

test_that("Scenario B: hyperspectral (cube -> spectra -> multiclass mask)", {
  cube <- at_example_image("cube")
  regions <- at_layer("regions", labels = c("r1", "r2", "bg"))
  regions <- regions |>
    at_layer_add(at_roi_circle(38, 38, 4, label = "r1")) |>
    at_layer_add(at_roi_circle(90, 77, 4, label = "r2")) |>
    at_layer_add(at_roi_rect(60, 20, 70, 30, label = "bg"))
  proj <- at_project(cube, regions)

  sp <- at_extract_spectrum(proj)
  s1 <- sp$value[sp$label == "r1"]
  s2 <- sp$value[sp$label == "r2"]
  sb <- sp$value[sp$label == "bg"]
  # The two planted signatures are clearly distinguishable, and from background.
  expect_gt(mean(abs(s1 - s2)), 1000)
  expect_gt(mean(abs(s1 - sb)), 300)
  expect_s3_class(at_plot_spectrum(sp), "ggplot")

  m <- at_mask(proj, "multiclass")
  expect_equal(nrow(at_mask_legend(m)), 3L)
})

test_that("Scenario C: batch session survives a crash and resumes", {
  skip_if_not_installed("tiff")
  sess <- at_example_session(5)
  add_roi_to <- function(session, i, label, rect) {
    proj <- at_current(at_goto(session, i))
    proj <- at_add_roi(proj, names(proj$layers)[1],
                       do.call(at_roi_rect, c(as.list(rect), label = label)))
    session$projects[[i]] <- proj
    at_set_status(session, i, "complete")
  }
  for (i in 1:3) sess <- add_roi_to(sess, i, "tumour", c(10, 10, 50, 50))
  at_save_session(sess)
  path <- file.path(sess$out_dir, "_session.rds")

  # Simulate a crash: drop the object and reload from disk.
  rm(sess)
  sess2 <- at_resume(path)
  expect_equal(sum(at_session_status(sess2)$status == "complete"), 3L)
  expect_false(is.null(sess2$projects[[1]]))
  expect_equal(nrow(at_rois(sess2$projects[[1]])), 1L)

  for (i in 4:5) sess2 <- add_roi_to(sess2, i, "stroma", c(20, 20, 60, 60))

  dir <- withr::local_tempdir()
  receipt <- suppressMessages(
    at_export_all(sess2, dir, scope = "complete",
                  formats = c("geojson", "mask_tiff"), progress = FALSE)
  )
  expect_true(all(receipt$status == "ok"))
  expect_true(all(file.exists(receipt$path)))
  expect_equal(length(unique(receipt$image)), 5L)
})

test_that("Scenario D: project -> GeoJSON -> project -> mask -> ROIs preserves data", {
  skip_if_not_installed("tiff")
  proj <- at_example_project()
  dir <- withr::local_tempdir()

  # Hop 1: project -> GeoJSON -> project.
  g <- file.path(dir, "a.geojson")
  at_write_geojson(proj, g)
  layers <- at_read_geojson(g)
  proj2 <- at_project(proj$image)
  for (nm in names(layers)) proj2 <- at_add_layer(proj2, layers[[nm]])
  expect_setequal(at_rois(proj2)$label, at_rois(proj)$label)
  expect_equal(sf::st_coordinates(at_rois(proj)$geometry),
               sf::st_coordinates(at_rois(proj2)$geometry), tolerance = 1e-9)

  # Hop 2: project -> mask -> mask file -> ROIs -> project.
  m <- at_mask(proj2, "labelled")
  p <- file.path(dir, "m.tif")
  at_write_mask(m, p)
  lyr <- at_read_mask(p)
  proj3 <- at_add_layer(at_project(proj$image), lyr)

  # The example ROIs are rectangles, so pixel sets round-trip exactly.
  d <- dim(as.matrix(m))
  m3 <- at_mask(proj3, "binary", dims = c(d[2], d[1]))
  expect_identical(as.matrix(m) != 0, as.matrix(m3))
})
