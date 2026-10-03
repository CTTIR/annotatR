test_that('relinking between built-in readers replaces backend-dependent image state', {
  skip_if_not_installed('tiff')
  dir <- withr::local_tempdir()
  path <- file.path(dir,'rgb.tif')
  tiff::writeTIFF(array(rep(c(0,1,1,0),3),c(2,2,3)),path,
                  bits.per.sample=8L,compression='none')
  img <- at_read_image(path,backend='raster')
  # Stale reader metadata must not leak into the replacement reader's image.
  img$meta$old_reader_field <- 'old'
  img$pixel_size <- c(2,3); img$pixel_unit <- 'um'
  p <- at_project(img,at_layer('L'),entry_id='retained-entry')
  p <- at_add_roi(p,'L',at_roi_rect(0,0,1,1,'retained'))
  fresh <- at_read_image(path,backend='tiff')
  linked <- at_relink_source(p,path,backend='tiff')
  expect_identical(linked$layers,p$layers)
  expect_identical(linked$meta,p$meta)
  saved <- file.path(dir,'linked.rds'); at_save_project(linked,saved)
  for (got in list(linked,at_load_project(saved))) {
    expect_identical(got$image$backend,'tiff')
    expect_identical(got$image$source_descriptor$backend,got$image$backend)
    expect_equal(at_tile(got$image),at_tile(fresh))
    fields <- c('band_names','dtype','pixel_size','pixel_unit','wavelength_unit','meta')
    expect_identical(got$image[fields],fresh[fields])
    expect_identical(got$layers,p$layers)
  }
  # The image-only API also adopts the replacement's complete image state.
  reverse <- at_relink_source(linked$image,path,backend='raster')
  expect_identical(reverse$backend,'raster')
  expect_equal(at_tile(reverse),at_tile(at_read_image(path,backend='raster')))
})

test_that('saved inspection includes source schemas without materializing pixels', {
  skip_if_not_installed('tiff')
  dir <- withr::local_tempdir(); path <- file.path(dir,'pixels.tif')
  tiff::writeTIFF(matrix(0,2,2),path,bits.per.sample=8L,compression='none')
  p <- at_project(at_read_image(path,backend='raster'))
  s <- at_session(path,out_dir=dir); s$projects[[1]] <- p
  project_path <- file.path(dir,'p.rds'); session_path <- file.path(dir,'s.rds')
  bad <- p; bad$image$source_descriptor$schema_version <- 99L
  saveRDS(bad,project_path)
  s$projects[[1]] <- bad; saveRDS(s,session_path)
  expect_error(at_load_project(project_path),'Unsupported source schema')
  expect_error(at_load_session(session_path),'Unsupported source schema')
  testthat::local_mocked_bindings(at_read_image=function(...) stop('Unexpected pixel read'),.package='annotatR')
  for (saved in c(project_path,session_path)) {
    before <- readBin(saved,'raw',file.info(saved)$size)
    report <- at_inspect_saved(saved)
    expect_false(report$valid)
    expect_match(report$issues,'Unsupported source schema')
    expect_match(report$sources[[1]]$issue,'Unsupported source schema')
    expect_identical(readBin(saved,'raw',file.info(saved)$size),before)
  }
  # Availability is independent of a checkpoint's structural/schema validity.
  for (availability in c('available','changed','missing','unresolved')) {
    if (availability=='changed') Sys.setFileTime(path,Sys.time()+20)
    if (availability=='missing') unlink(path)
    candidate <- p
    if (availability=='unresolved') candidate$image <- tiny_image()
    s$projects[[1]] <- candidate
    saveRDS(candidate,project_path); saveRDS(s,session_path)
    for (saved in c(project_path,session_path)) {
      before <- readBin(saved,'raw',file.info(saved)$size)
      report <- at_inspect_saved(saved)
      expect_true(report$valid)
      expect_length(report$issues,0L)
      expect_identical(report$sources[[1]]$status,availability)
      expect_identical(readBin(saved,'raw',file.info(saved)$size),before)
    }
  }
})
