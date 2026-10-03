test_that("A01 stripped project reopens identical pixels in a fresh process", {
  skip_if_not_installed("tiff")
  dir <- tempfile(); dir.create(dir); withr::defer(unlink(dir,recursive=TRUE))
  path <- file.path(dir,"pixels.tif"); saved <- file.path(dir,"project.rds")
  tiff::writeTIFF(matrix(c(0,1,1,0),2,2), path,
                  bits.per.sample = 8L, compression = "none")
  p <- at_project(at_read_image(path),at_layer("L"))
  env <- new.env(parent=globalenv())
  sys.source(system.file("shiny","annotatR","modules","mod_session.R",package="annotatR"),env)
  at_save_project(env$.lite_project(p),saved)
  tile <- audit_fresh("at_tile(at_load_project(args$path)$image)",list(path=saved))
  expect_equal(dim(tile), c(2L,2L,1L))
  expect_equal(as.vector(tile), c(0,255,255,0))
})

test_that("A07 loaded ROI IDs survive fresh-process additions without collisions", {
  .reset_id_counter()
  layer <- at_layer("L")
  for (i in 1:4) layer <- at_layer_add(layer,at_roi_rect(i,i,i+1,i+1,"a"))
  p <- at_project(tiny_image(),layer)
  ids <- at_rois(p)$roi_id
  path <- tempfile(fileext=".rds"); withr::defer(unlink(path))
  at_save_project(p,path)
  result <- audit_fresh(paste(
    "p <- at_load_project(args$path)",
    "p <- at_add_roi(p,'L',at_roi_rect(6,6,7,7,'a'))",
    "at_rois(p)$roi_id",sep=";"),list(path=path))
  expect_identical(result[1:4],ids)
  expect_length(result,5L)
  expect_identical(anyDuplicated(result),0L)
})

test_that("A08 duplicate image basenames export distinct successful artifacts", {
  skip_if_not_installed("tiff")
  dir <- tempfile(); dir.create(dir); withr::defer(unlink(dir,recursive=TRUE))
  dirs <- file.path(dir,c("A","B")); lapply(dirs,dir.create)
  paths <- file.path(dirs,"same.tif")
  for (path in paths) tiff::writeTIFF(matrix(0,10,10),path)
  s <- at_session(paths)
  s$projects <- lapply(c("first","second"),function(label)
    at_project(tiny_image(),at_layer_add(at_layer("L"),square_roi(label))))
  rc <- at_export_all(s,file.path(dir,"out"),formats="geojson",scope="all",overwrite=TRUE,progress=FALSE)
  expect_equal(sum(rc$status == "ok"),2L)
  expect_equal(length(unique(rc$path)),2L)
  labels <- vapply(rc$path,function(path) at_read_geojson(path)[[1]]$labels,character(1))
  expect_identical(unname(labels),c("first","second"))
})

test_that("A22 project names cannot escape mask export directory", {
  skip_if_not_installed("tiff")
  dir <- tempfile(); dir.create(dir); withr::defer(unlink(dir,recursive=TRUE))
  out <- file.path(dir,"out"); dir.create(out)
  p <- at_project(tiny_image(),at_layer_add(at_layer("L"),square_roi()),name="../escaped")
  # Rejection or safe encoding is permitted; creating an outside file is not.
  rc <- at_write_masks(p,out,per="project")
  expect_identical(rc$status, "ok")
  expect_true(all(file.exists(rc$path)))
  expect_false(file.exists(file.path(dir,"escaped.tif")))
  expect_true(all(startsWith(normalizePath(rc$path),paste0(normalizePath(out),"/"))))
})

test_that("A23 default session path honours overwrite FALSE", {
  s <- demo_session(); withr::defer(unlink(s$out_dir,recursive=TRUE))
  at_save_session(s)
  path <- file.path(s$out_dir,"_session.rds")
  before <- readBin(path,"raw",n=file.info(path)$size)
  s$manifest$status[1] <- "complete"
  expect_error(at_save_session(s,overwrite=FALSE),"[Ee]xist|[Oo]verwrite")
  expect_identical(readBin(path,"raw",n=file.info(path)$size),before)
})
