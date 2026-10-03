persistence_cube <- function(dir) {
  path <- file.path(dir, 'tiny_SpecCube.dat')
  con <- file(path, 'wb')
  writeBin(as.double(c(0,0,0,1:12)), con, size = 4L, endian = 'big'); close(con)
  at_read_image(path, backend = 'tivita', nx = 3L, ny = 2L, nb = 2L,
                wavelengths = c(500, 600))
}

test_that('versioned spectral descriptor reopens in a fresh process with options', {
  dir <- withr::local_tempdir(); img <- persistence_cube(dir)
  p <- at_project(img, at_layer('L')); path <- file.path(dir, 'p.rds')
  at_save_project(p, path)
  disk <- readRDS(path)
  expect_identical(disk$provenance$schema_version, 1L)
  expect_identical(disk$image$source_descriptor$schema_version, 1L)
  expect_null(disk$image$handle)
  result <- audit_fresh(paste("p <- at_load_project(args$path)",
    "p <- at_add_roi(p, 'L', at_roi_rect(0,0,1,1,'new'))",
    "list(tile=at_tile(p$image), bands=at_wavelengths(p$image), n=nrow(at_rois(p)))", sep=';'), list(path=path))
  expect_equal(result$tile, at_tile(img)); expect_equal(result$bands, c(500,600))
  expect_equal(result$n, 1L)
})

test_that('missing and changed sources stay inspectable and require explicit relink', {
  dir <- withr::local_tempdir(); img <- persistence_cube(dir)
  expected <- at_tile(img)
  p <- at_project(img); path <- file.path(dir, 'p.rds'); at_save_project(p,path)
  replacement <- file.path(dir,'relocated_SpecCube.dat'); file.copy(img$source,replacement)
  unlink(img$source)
  loaded <- at_load_project(path)
  expect_equal(at_inspect_source(loaded)$status, 'missing')
  expect_error(at_tile(loaded$image), 'at_relink_source')
  linked <- at_relink_source(loaded,replacement)
  expect_equal(at_tile(linked$image),expected)
  Sys.setFileTime(replacement, Sys.time()+10)
  at_save_project(linked, file.path(dir,'linked.rds'))
  changed <- at_load_project(file.path(dir,'linked.rds'))
  expect_equal(at_inspect_source(changed)$status, 'changed')
  expect_error(at_tile(changed$image), 'at_relink_source')
  expect_equal(at_tile(at_relink_source(changed,replacement)$image), expected)
})

test_that('default sessions use isolated checkpoint destinations', {
  dir <- withr::local_tempdir(); img <- persistence_cube(dir)
  a <- at_session(img$source); b <- at_session(img$source)
  withr::defer(unlink(c(a$out_dir,b$out_dir),recursive=TRUE))
  expect_false(identical(a$out_dir,b$out_dir))
  at_save_session(a); at_save_session(b)
  expect_error(at_save_session(a), 'already exists')
  expect_identical(at_resume(file.path(a$out_dir,'_session.rds'))$manifest$entry_id,a$manifest$entry_id)
})

test_that('atomic writes roll back checked Unix and Windows replacement failures', {
  path <- file.path(withr::local_tempdir(),'checkpoint.rds'); saveRDS('old',path)
  for (platform in c('unix','windows')) {
    rename <- function(from,to) if (grepl('stage-',basename(from))) FALSE else file.rename(from,to)
    expect_error(.atomic_save_rds('new',path,overwrite=TRUE,platform=platform,rename=rename), 'replace')
    expect_identical(readRDS(path),'old')
    .atomic_save_rds('ok',path,overwrite=TRUE,platform=platform)
    expect_identical(readRDS(path),'ok'); saveRDS('old',path)
  }
  expect_error(.atomic_save_rds('new',path,overwrite=TRUE,
    writer=function(object,path) { writeLines('partial',path); stop('injected write') }), 'injected write')
  expect_identical(readRDS(path),'old')
})

test_that('checkpoint files are immutable across resume and failed manifest publication', {
  dir <- withr::local_tempdir(); img <- persistence_cube(dir)
  s <- at_session(img$source,out_dir=dir)
  s$projects[[1]] <- at_project(img,at_layer('L'),entry_id=s$manifest$entry_id[1])
  s <- .save_checkpoint(s,1)
  manifest <- file.path(dir,'_session.rds'); before <- readRDS(manifest)
  old_project <- before$manifest$project_path[1]
  s <- at_resume(manifest)
  s$projects[[1]] <- at_add_roi(at_current(s),'L',at_roi_rect(0,0,1,1,'new'))
  for (platform in c('unix','windows')) {
    failing <- function(object,path,overwrite=FALSE) {
      .atomic_save_rds(object,path,overwrite=overwrite,platform=platform,
        rename=function(from,to) {
          if (basename(to)=='_session.rds' && grepl('stage-',basename(from))) return(FALSE)
          file.rename(from,to)
        })
    }
    expect_error(.save_checkpoint(s,1,write=failing),'replace checkpoint')
    expect_identical(readRDS(manifest),before)
    expect_equal(nrow(at_rois(at_load_project(old_project))),0)
    expect_equal(at_tile(at_current(at_resume(manifest))$image),at_tile(img))
  }
  expect_error(.save_checkpoint(s,1,write=function(object,path,overwrite=FALSE) {
    .atomic_save_rds(object,path,overwrite=overwrite,writer=function(object,path) {
      writeLines('partial',path); stop('project serialization failure')
    })
  }),'project serialization failure')
  expect_identical(readRDS(manifest),before)
  saved <- .save_checkpoint(s,1)
  expect_false(identical(saved$manifest$project_path[1],old_project))
  expect_equal(nrow(at_rois(at_current(at_resume(manifest)))),1)
})

test_that('launcher preserves supplied in-memory image and project sources', {
  img <- new_annot_image('memory:only', 'envi',c(3,2),1L,list(c(3,2)),2L,
                         handle=list(data=array(as.double(1:12),c(2,3,2))))
  a <- .to_session(img,'a',NULL,NULL)
  b <- .to_session(at_project(img,at_layer('L')),'a',NULL,NULL)
  expect_equal(at_tile(at_current(a)$image),img$handle$data)
  expect_equal(at_tile(at_current(b)$image),img$handle$data)
  expect_false(identical(a$out_dir,b$out_dir))
  expect_identical(at_current(a)$meta$entry_id,a$manifest$entry_id[1])
})

test_that('checkpoint refuses a missing referenced project before publication', {
  dir <- withr::local_tempdir(); img <- persistence_cube(dir)
  s <- at_session(img$source,out_dir=dir)
  s$manifest$project_path[1] <- file.path(dir,'absent.rds')
  expect_error(.save_checkpoint(s,1),'exist|Missing')
  expect_false(file.exists(file.path(dir,'_session.rds')))
})
