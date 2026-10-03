# Literal oracles use an anisotropic pyramid; a separate fixture is non-dyadic.
level_image <- function() new_annot_image(
  "levels", "raster", c(64L, 48L), 3L,
  list(c(64L, 48L), c(16L, 24L), c(8L, 12L)), 1L)
level_project <- function() at_project(level_image(), at_layer_add(at_layer("L"),
  at_roi_rect(2, 3, 5, 7, "region", level = 1L, id = "level-roi")))
level_bbox <- function(r) unname(as.numeric(sf::st_bbox(r$geometry)))

test_that("level tables declare the coordinates they actually contain", {
  p <- level_project(); before <- p$layers$L$rois[[1]]
  rt <- at_rois(p)
  expect_identical(rt$level, 0L)
  expect_identical(rt$source_level, 1L)
  expect_equal(unname(as.numeric(sf::st_bbox(rt$geometry))), c(8, 6, 20, 14))
  expect_equal(rt$area_px, 96)
  expect_identical(p$layers$L$rois[[1]], before)
  expect_identical(at_rois(at_project(level_image()))$source_level, integer())
  expect_error(at_layer_rois(p$layers$L), "image|Image")
})

for (fmt in c("csv", "geojson", "qupath")) {
  test_that(paste(fmt, "exports declare output coordinates and preserve masks"), {
    p <- level_project(); f <- tempfile(); withr::defer(unlink(f))
    for (lev in if (fmt == "csv") 0L else 0:2) {
      if (fmt == "csv") {
        at_write_rois_csv(p, f, overwrite = TRUE)
        props <- utils::read.csv(f)
        lyr <- at_read_rois_csv(f)
      } else {
        writer <- if (fmt == "qupath") at_write_qupath else at_write_geojson
        writer(p, f, level = lev, overwrite = TRUE)
        props <- jsonlite::read_json(f)$features[[1]]$properties
        lyr <- if (fmt == "qupath") at_read_qupath(f) else at_read_geojson(f)[[1]]
      }
      expect_equal(props$level, lev)
      expect_equal(props$source_level, 1L)
      expect_identical(props$coordinate_schema, "annotatR-pixel-level-v1")
      expect_identical(lyr$rois[[1]]$id, "level-roi")
      expect_equal(lyr$rois[[1]]$level, lev)
      expected_bbox <- list(c(8,6,20,14), c(2,3,5,7), c(1,1.5,2.5,3.5))[[lev+1L]]
      expect_equal(level_bbox(lyr$rois[[1]]), expected_bbox, tolerance = 1e-12)
      expect_identical(as.matrix(at_mask(at_project(p$image, lyr))), as.matrix(at_mask(p)))
    }
  })
}

test_that("legacy metadata is overridden only in explicit import mode", {
  f <- tempfile(); withr::defer(unlink(f))
  writeLines('"roi_id","label","level","geometry"\n"legacy","a",1,"POLYGON ((8 6, 20 6, 20 14, 8 14, 8 6))"', f)
  expect_error(at_read_rois_csv(f), "[Aa]mbiguous")
  expect_equal(at_read_rois_csv(f, legacy_levels="recorded")$rois[[1]]$level, 1L)
  expect_equal(at_read_rois_csv(f, coordinate_level = 0L)$rois[[1]]$level, 0L)
  legacy <- at_read_rois_csv(f, coordinate_level=0L)
  expected <- matrix(FALSE,48,64); expected[7:14,9:20] <- TRUE
  expect_identical(as.matrix(at_mask(at_project(level_image(),legacy))),expected)
  writeLines('{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"label":"a","level":1},"geometry":{"type":"Point","coordinates":[8,6]}}]}', f)
  expect_error(at_read_geojson(f), "[Aa]mbiguous")
  expect_equal(at_read_geojson(f, legacy_levels="recorded")[[1]]$rois[[1]]$level, 1L)
  expect_equal(at_read_geojson(f, coordinate_level = 0L)[[1]]$rois[[1]]$level, 0L)
  recorded <- at_project(level_image(),at_read_geojson(f,legacy_levels="recorded")[[1]])
  normalized <- at_project(level_image(),at_read_geojson(f,coordinate_level=0L)[[1]])
  expect_equal(unname(as.numeric(sf::st_bbox(at_rois(recorded)$geometry))),c(32,12,32,12))
  expect_equal(unname(as.numeric(sf::st_bbox(at_rois(normalized)$geometry))),c(8,6,8,6))
})

test_that("standalone computations require real scale only when changing levels", {
  img <- level_image(); a <- at_roi_rect(8,6,20,14,"a")
  b <- at_roi_rect(2,3,5,7,"b", level=1L)
  for (op in list(at_roi_union, at_roi_intersect, at_roi_difference, at_roi_symdiff)) {
    expect_error(op(a,b), "image|Image|level")
    result <- suppressWarnings(op(a,b,image=img))
    expect_equal(result$level, 0L)
  }
  expect_equal(level_bbox(at_roi_union(a,b,image=img)), c(8,6,20,14))
  expect_equal(at_roi_intersect(a,b,image=img)$level, 0L)
  expect_equal(at_roi_union(b,b)$level, 1L)
  expect_error(at_roi_overlaps(a,b), "image|Image")
  expect_true(at_roi_overlaps(a,b,image=img))
  expect_true(at_roi_overlaps(b,b))
  pt <- at_roi_point(6,3,"p",level=1L)
  expect_error(at_roi_distance(b,pt), "image|Image")
  expect_equal(at_roi_distance(b,pt,image=img), 4)
  lyr <- at_layer_add(at_layer_add(at_layer("L"),a),b)
  expect_error(at_rois_overlap(lyr), "image|Image")
  expect_equal(at_rois_overlap(lyr,image=img)$overlap_px, 96)
  expect_error(at_roi_area(b), "image|Image")
  expect_equal(at_roi_area(b,image=img), 96)
  expect_equal(at_roi_area(b,level=1L), 12)
  expect_error(at_mask(b,dims=c(64,48)), "image|Image")
  expected <- matrix(FALSE,48,64); expected[7:14,9:20] <- TRUE
  expect_identical(as.matrix(at_mask(b,image=img)),expected)
  expect_equal(sum(at_mask(b,level=1L,dims=c(16,24))),12)
  expect_error(at_transform(b,1,3,img), "pyramid|level|Level")
  expect_error(.to_level0(b$geometry,3L,img), "pyramid|level|Level")
})

test_that("anisotropic per-ROI export preserves project selection at each level", {
  skip_if_not_installed("tiff")
  p <- level_project(); d <- tempfile(); withr::defer(unlink(d,recursive=TRUE))
  for (lev in 0:2) {
    receipt <- at_write_masks(p,d,per="roi",type="binary",level=lev,overwrite=TRUE)
    expected <- matrix(0L, c(48,24,12)[lev+1L], c(64,16,8)[lev+1L])
    if (lev==0) expected[7:14,9:20] <- 1L
    if (lev==1) expected[4:7,3:5] <- 1L
    if (lev==2) expected[2:3,2] <- 1L
    expect_equal(tiff::readTIFF(receipt$path,as.is=TRUE),expected)
    expect_equal(as.matrix(at_mask(p,level=lev))*1L,expected)
    imported <- at_read_mask(receipt$path)
    expect_equal(imported$rois[[1]]$level,lev)
    expect_identical(as.matrix(at_mask(at_project(p$image,imported),level=lev)),expected!=0L)
  }
})

test_that("plot sampling retains full level-zero cell extents including partial cells", {
  img <- new_annot_image("display-cells", "raster", c(11L,7L), 1L,
    list(c(11L,7L)), 1L,handle=list(data=array(seq_len(77),c(7,11,1))))
  .tile_cache_clear(); withr::defer(.tile_cache_clear())
  built <- ggplot2::ggplot_build(at_plot_image(img,max_dim=4))$data[[1]]
  expect_equal(sort(unique(built$xmin)), c(0,3,6,9))
  expect_equal(sort(unique(built$xmax)), c(3,6,9,11))
  expect_equal(sort(unique(pmin(built$ymin,built$ymax))), c(-7,-6,-3))
  expect_equal(sort(unique(pmax(built$ymin,built$ymax))), c(-6,-3,0))
  img <- level_image()
  testthat::local_mocked_bindings(at_tile=function(img,level,...) array(1,c(img$level_dims[[level+1]][2:1],1)))
  for (lev in 0:2) {
    built <- ggplot2::ggplot_build(at_plot_image(img,level=lev,max_dim=100))$data[[1]]
    expect_equal(range(c(built$xmin,built$xmax)),c(0,64))
    expect_equal(range(c(built$ymin,built$ymax)),c(-48,0))
  }
})


test_that("non-dyadic geometry round trips retain stored metadata and precision", {
  img <- new_annot_image("non-dyadic", "raster", c(63L,47L),2L,
    list(c(63L,47L),c(17L,23L)),1L)
  r <- at_roi_rect(1.25,2.75,13.5,19.25,"a",level=1L,id="stable-id")
  r0 <- at_transform(r,1L,0L,img)
  expect_equal(level_bbox(r0), c(1.25*63/17,2.75*47/23,13.5*63/17,19.25*47/23),
               tolerance=1e-12)
  back <- at_transform(r0,0L,1L,img)
  expect_equal(sf::st_coordinates(back$geometry),sf::st_coordinates(r$geometry),tolerance=1e-12)
  expect_identical(back$id,r$id)
  expect_identical(back$level,r$level)
  expect_identical(back$created,r$created)
})

test_that("NPY level metadata survives a nonzero-level mask round trip", {
  p <- level_project(); m <- at_mask(p,level=1L)
  f <- tempfile(fileext=".npy"); withr::defer(unlink(c(f,paste0(f,".legend.json"))))
  at_write_npy(m,f)
  back <- at_read_npy(f)
  expect_identical(attr(back,"level"),1L)
  expect_identical(as.matrix(back),as.matrix(m)*1L)
  expect_identical(attr(at_read_npy(f,level=0L),"level"),0L)
})

test_that("set-operation geometry has literal image-level areas", {
  img <- level_image(); a <- at_roi_rect(8,6,20,14,"a")
  b <- at_roi_rect(3,5,6,9,"b",level=1L)
  expect_equal(at_roi_area(at_roi_union(a,b,image=img)),160)
  expect_equal(at_roi_area(at_roi_intersect(a,b,image=img)),32)
  expect_equal(at_roi_area(at_roi_difference(a,b,image=img)),64)
  expect_equal(at_roi_area(at_roi_symdiff(a,b,image=img)),128)
  expect_equal(level_bbox(at_roi_intersect(a,b,image=img)),c(12,10,20,14))
  expect_equal(at_roi_union(b,a,image=img)$level,0L)
})


test_that("legacy QuPath levels require interpretation and fractional levels are rejected", {
  f <- tempfile(); withr::defer(unlink(f))
  writeLines('{"type":"FeatureCollection","features":[{"id":"legacy","type":"Feature","properties":{"level":1},"geometry":{"type":"Point","coordinates":[8,6]}}]}',f)
  expect_error(at_read_qupath(f),"[Aa]mbiguous")
  expect_equal(level_bbox(at_read_qupath(f,legacy_levels="recorded")$rois[[1]]),c(8,6,8,6))
  expect_equal(at_read_qupath(f,legacy_levels="recorded")$rois[[1]]$level,1L)
  expect_equal(at_read_qupath(f,coordinate_level=0L)$rois[[1]]$level,0L)
  writeLines('{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"level":1.5,"coordinate_schema":"annotatR-pixel-level-v1"},"geometry":{"type":"Point","coordinates":[8,6]}}]}',f)
  expect_error(at_read_geojson(f),"integer|whole")
  expect_error(at_read_qupath(f),"integer|whole")
  writeLines('"label","level","coordinate_schema","geometry"\n"a",1.5,"annotatR-pixel-level-v1","POINT (8 6)"',f)
  expect_error(at_read_rois_csv(f),"integer|whole")
})

test_that("GeoJSON feature construction validates levels before coercion", {
  feature <- list(geometry=list(type="Point",coordinates=c(8,6)))
  expect_error(at_roi_from_geojson(feature,level=1.5),"integer|whole")
})

test_that("anisotropic extraction and full masks select the same literal pixels", {
  p <- level_project()
  testthat::local_mocked_bindings(at_tile=function(img,level,xrange,yrange,bands=NULL,...) {
    d <- img$level_dims[[level+1L]]
    a <- array(seq_len(prod(d)),c(d[2],d[1],1L))
    a[seq.int(yrange[1],yrange[2]),seq.int(xrange[1],xrange[2]),,drop=FALSE]
  })
  for (lev in 0:2) {
    pixels <- at_extract_pixels(p,level=lev)
    stats <- at_extract(p,level=lev,stat="n")
    expect_equal(nrow(pixels),c(96,12,2)[lev+1L])
    expect_equal(stats$value,c(96,12,2)[lev+1L])
    selected <- as.matrix(at_mask(p,level=lev))
    expect_equal(as.integer(selected[cbind(pixels$y,pixels$x)]),rep(1L,nrow(pixels)))
    if (lev==1) expect_equal(sort(pixels$value),c(52:55,76:79,100:103))
  }
})

test_that("alternate extraction images use their own registered pyramid grid", {
  p <- level_project()
  alternate <- new_annot_image("alternate", "raster", c(64L,48L),2L,
    list(c(64L,48L),c(32L,12L)),1L,wavelengths=500)
  testthat::local_mocked_bindings(at_tile=function(img,level,xrange,yrange,bands=NULL,...) {
    d <- img$level_dims[[level+1L]]
    a <- array(seq_len(prod(d)),c(d[2],d[1],1L))
    a[seq.int(yrange[1],yrange[2]),seq.int(xrange[1],xrange[2]),,drop=FALSE]
  })
  expected <- c(50,51,62,63,74,75,86,87,98,99,110,111)
  pixels <- at_extract_pixels(p,img=alternate,level=1L)
  expect_equal(sort(pixels$value),expected)
  expect_equal(sort(unique(pixels$x)),5:10)
  expect_equal(sort(unique(pixels$y)),2:3)
  stats <- at_extract(p,img=alternate,level=1L,stat="mean")
  expect_equal(stats$value,80.5)
  expect_equal(at_extract_spectrum(p,img=alternate,level=1L)$value,80.5)
  wrong <- alternate; wrong$dims <- c(65L,48L); wrong$level_dims[[1]] <- c(65L,48L)
  expect_error(at_extract(p,img=wrong),"extent|grid|registration")
  expect_error(at_extract_pixels(p,img=wrong),"extent|grid|registration")
  expect_error(at_extract_spectrum(p,img=wrong),"extent|grid|registration")
})

test_that("CSV geometry precision is independent of session display digits", {
  withr::local_options(list(digits=3L, scipen=-9L))
  img <- new_annot_image("csv-non-dyadic", "raster", c(63L,47L),2L,
    list(c(63L,47L),c(17L,23L)),1L)
  roi <- at_roi_rect(1.25,2.75,13.5,19.25,"a",level=1L,id="csv-stable")
  project <- at_project(img,at_layer_add(at_layer("L"),roi))
  path <- tempfile(fileext=".csv"); withr::defer(unlink(path))
  at_write_rois_csv(project,path)
  imported <- at_read_rois_csv(path)$rois[[1]]
  # Literal source vertices scaled by independently stated width/height ratios.
  expected <- rbind(c(1.25*63/17,2.75*47/23), c(13.5*63/17,2.75*47/23),
                    c(13.5*63/17,19.25*47/23), c(1.25*63/17,19.25*47/23),
                    c(1.25*63/17,2.75*47/23))
  actual <- unname(sf::st_coordinates(imported$geometry)[,1:2])
  expect_lte(max(abs((actual-expected)/expected)),1e-12)
  expect_identical(imported$id,"csv-stable")
  expect_identical(imported$level,0L)
  metadata <- utils::read.csv(path)
  expect_identical(metadata$source_level,1L)
  expect_identical(metadata$coordinate_schema,"annotatR-pixel-level-v1")
  expect_identical(project$layers$L$rois[[1]],roi)
})

for (entry in c("at_plot", "autoplot")) {
  test_that(paste(entry,"threads layer image context into level-zero plot geometry"), {
    project <- level_project()
    draw <- if (entry == "at_plot") at_plot else ggplot2::autoplot
    expect_error(draw(project$layers$L),"image pyramid dimensions")
    plot <- draw(project$layers$L,image=project$image)
    expected <- rbind(c(8,6),c(20,6),c(20,14),c(8,14),c(8,6))
    expect_equal(unname(sf::st_coordinates(plot$data$geometry)[,1:2]),expected)
    at_zero <- at_layer_add(at_layer("zero"),at_roi_rect(1,2,3,4,"a"))
    expect_equal(unname(as.numeric(sf::st_bbox(draw(at_zero)$data$geometry))),c(1,2,3,4))
  })
}
