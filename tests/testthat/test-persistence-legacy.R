legacy_copy <- function(name, dir) {
  fixtures <- test_path('..','fixtures','legacy-f69bf20')
  target <- file.path(dir,'source.tif')
  file.copy(file.path(fixtures,'source.tif'),target,overwrite=TRUE)
  obj <- readRDS(file.path(fixtures,name))
  rebase <- function(p) {
    if (is.null(p)) return(NULL)
    if (p$image$source == '/tmp/annotatr-roadmap-legacy/source.tif') {
      p$meta$fixture_rebase <- list(original=p$image$source,replacement=target)
      p$image$source <- target
    }
    p
  }
  if (inherits(obj,'annot_session')) {
    obj$meta$fixture_rebase <- list(original=obj$manifest$path,replacement=target)
    obj$manifest$path[] <- target; obj$out_dir <- dir
    obj$projects <- lapply(obj$projects,rebase)
  } else obj <- rebase(obj)
  path <- file.path(dir,name); saveRDS(obj,path); path
}

test_that('genuine legacy annotations survive explicit TIFF reader revalidation', {
  skip_if_not_installed('tiff')
  dir <- withr::local_tempdir()
  for (name in c('project-full.rds','project-lite.rds')) {
    path <- legacy_copy(name,dir)
    original <- readRDS(path); loaded <- at_load_project(path)
    expect_identical(at_rois(loaded)$roi_id,'roi_000000001')
    expect_identical(at_rois(loaded)$geometry,at_rois(original)$geometry)
    if (name=='project-lite.rds') {
      expect_true(at_inspect_source(loaded)$options_inferred)
      expect_null(loaded$image$handle)
      expect_error(at_tile(loaded$image),'metadata|revalidate')
      loaded <- at_relink_source(loaded,loaded$image$source)
      expect_identical(at_rois(loaded)$geometry,at_rois(original)$geometry)
      expect_identical(at_rois(loaded)$roi_id,'roi_000000001')
    }
    expect_equal(as.vector(at_tile(loaded$image)),c(0,255,255,0))
    expect_s3_class(at_plot_image(loaded$image),'ggplot')
    expect_equal(at_extract(loaded)$value,0)
  }
  p <- at_load_project(legacy_copy('project-memory.rds',dir))
  expect_equal(as.vector(at_tile(p$image)),as.double(1:12))
  path <- file.path(dir,'memory-new.rds'); at_save_project(p,path)
  expect_equal(as.vector(at_tile(at_load_project(path)$image)),as.double(1:12))
  expect_false(is.null(readRDS(path)$image$handle))
})

test_that('genuine repeated-source legacy queue migrates positionally and keeps IDs', {
  dir <- withr::local_tempdir(); path <- legacy_copy('session-lite.rds',dir)
  s <- at_resume(path)
  expect_length(unique(s$manifest$entry_id),2)
  expect_equal(vapply(s$projects,function(p) at_rois(p)$label,character(1)),c('first','second'))
  expect_identical(at_rois(s$projects[[1]])$roi_id,'roi_000000001')
  expect_null(s$projects[[1]]$image$handle)
  expect_error(at_tile(s$projects[[1]]$image),'metadata|revalidate')
  s$projects <- lapply(s$projects,function(p) at_relink_source(p,p$image$source))
  expect_identical(at_rois(s$projects[[1]])$roi_id,'roi_000000001')
  at_save_session(s,file.path(dir,'new.rds'))
  fresh <- audit_fresh("s <- at_resume(args$path); list(ids=s$manifest$entry_id, tile=at_tile(at_current(s)$image))",list(path=file.path(dir,'new.rds')))
  expect_identical(fresh$ids,s$manifest$entry_id)
  expect_equal(as.vector(fresh$tile),c(0,255,255,0))
})

test_that('ambiguous legacy structures are rejected without guessed repair', {
  dir <- withr::local_tempdir(); path <- legacy_copy('session-lite.rds',dir)
  s <- readRDS(path); s$manifest$entry_id <- c('one','two'); saveRDS(s,path)
  expect_error(at_resume(path),'Missing field|persisted queue identity')
  p <- demo_project(); p$layers[[1]]$rois[[2]]$id <- p$layers[[1]]$rois[[1]]$id
  saveRDS(p,path)
  expect_error(at_load_project(path),'duplicate ROI')
  p <- demo_project(); p$provenance$schema_version <- 99L; saveRDS(p,path)
  expect_error(at_load_project(path),'Unsupported project schema')
  p <- demo_project(); saveRDS(p,path)
  expect_equal(nrow(at_rois(at_load_project(path))),nrow(at_rois(p)))
  expect_equal(at_inspect_source(at_load_project(path))$status,'unresolved')
})

test_that('read-only checkpoint inspection reports ambiguous content without repair', {
  dir <- withr::local_tempdir(); path <- legacy_copy('session-lite.rds',dir)
  obj <- readRDS(path); obj$manifest$entry_id <- c('same','same'); saveRDS(obj,path)
  before <- readBin(path,'raw',file.info(path)$size)
  report <- at_inspect_saved(path)
  expect_false(report$valid); expect_true(length(report$issues)>0)
  expect_identical(readBin(path,'raw',file.info(path)$size),before)
})
