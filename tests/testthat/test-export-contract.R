test_that('derived mask filenames are contained, unique and retain display labels', {
  skip_if_not_installed('tiff')
  p <- at_project(small_image(), at_layer_add(at_layer('../L'), at_roi_rect(1,1,5,5,'a/b')), name='../escaped')
  p <- at_add_roi(p, at_roi_rect(7,1,10,5,'a\\b'), layer='../L')
  d <- withr::local_tempdir()
  rc <- at_write_masks(p,d,per='class')
  expect_identical(rc$status, c('ok','ok'))
  expect_length(unique(tolower(rc$path)),2)
  expect_true(all(startsWith(normalizePath(rc$path),paste0(normalizePath(d),'/'))))
  expect_setequal(rc$name,c('../escaped_a/b','../escaped_a\\b'))
  expect_true(all(file.exists(rc$sidecar_path)))
  expect_type(rc$bytes,'double')
})

test_that('failed mask jobs and existing sidecars preserve all item outcomes', {
  skip_if_not_installed('tiff')
  p <- demo_project(); d <- withr::local_tempdir()
  testthat::local_mocked_bindings(.write_legend_json=function(...) stop('injected legend failure'))
  rc <- at_write_masks(p,d,per='layer')
  expect_equal(nrow(rc), length(p$layers))
  expect_true(all(rc$status=='error'))
  expect_false(any(file.exists(rc$path)))
  expect_false(any(file.exists(rc$sidecar_path)))
})

test_that('bundle replacement stages all files and rolls back publication failures', {
  d <- withr::local_tempdir(); paths <- file.path(d,c('mask.tif','mask.tif.legend.json'))
  writeLines('old pixels', paths[1]); writeLines('old metadata',paths[2])
  expect_error(.export_bundle(paths,function(p) {writeLines('new',p[1]);stop('legend failed')},TRUE),'legend failed')
  expect_identical(readLines(paths[1]),'old pixels'); expect_identical(readLines(paths[2]),'old metadata')
  moves <- 0L
  rename <- function(a,b) {moves <<- moves+1L; if(moves==4L) return(FALSE); file.rename(a,b)}
  expect_error(.export_bundle(paths,function(p) lapply(p, function(x) writeLines('new',x)),TRUE,rename=rename),'publish')
  expect_identical(readLines(paths[1]),'old pixels'); expect_identical(readLines(paths[2]),'old metadata')
  expect_error(.export_bundle(paths,function(p) NULL,FALSE),'already exists')
})

test_that('batch preflight rejects symlink destinations before writing anything', {
  skip_on_os('windows')
  s <- at_example_session(1); d <- withr::local_tempdir(); outside <- withr::local_tempdir()
  expect_true(file.symlink(outside,file.path(d,'geojson')))
  expect_error(at_export_all(s,d,formats=c('csv','geojson'),scope='all',progress=FALSE),'[Ss]ymlink|containment')
  expect_length(list.files(outside),0)
  expect_false(dir.exists(file.path(d,'csv')))
})

test_that('receipts retain per-format materialization failures and skip existing bundles', {
  s <- at_example_session(2); d <- withr::local_tempdir()
  s$manifest$path[1] <- file.path(d,'missing.tif')
  rc <- suppressWarnings(at_export_all(s,d,formats=c('geojson','csv'),scope='all',progress=FALSE))
  expect_equal(nrow(rc),4)
  expect_equal(sum(rc$status=='error'),2)
  expect_type(rc$bytes,'double')
  rc2 <- suppressWarnings(at_export_all(s,d,formats=c('geojson','csv'),scope='all',progress=FALSE))
  expect_equal(sum(rc2$status=='skipped'),2)
  expect_equal(nrow(utils::read.csv(file.path(d,'_export_manifest.csv'))),4)
})

test_that('explicit single-file paths stay caller-selected and sidecars are checked', {
  m <- at_mask(demo_project()); d <- withr::local_tempdir(); p <- file.path(d,'chosen.npy')
  writeLines('prior sidecar',paste0(p,'.legend.json'))
  expect_error(at_write_npy(m,p),'already exists')
  expect_false(file.exists(p))
  at_write_npy(m,p,overwrite=TRUE)
  expect_identical(as.integer(at_read_npy(p)),as.integer(m))
})

test_that('actual output bundles disambiguate cross-format aliases and reserved names', {
  s <- at_example_session(2);s$manifest$export_stem <- c('same','same_qupath')
  d <- withr::local_tempdir()
  rc <- .export_session_items(s,1:2,d,c('geojson','qupath'),function(i) demo_project(),flat=TRUE)
  expect_identical(rc$status,rep('ok',4))
  expect_length(unique(tolower(rc$path)),4)
  s$manifest$export_stem <- c('A','a')
  rc <- .export_session_items(s,1:2,withr::local_tempdir(),'csv',function(i) demo_project(),flat=TRUE)
  expect_length(unique(tolower(rc$path)),2)
})

test_that('one format failure does not suppress siblings or hide a receipt publication failure', {
  s <- at_example_session(1); d <- withr::local_tempdir()
  testthat::local_mocked_bindings(at_write_qupath=function(...) stop('broken QuPath writer'))
  rc <- suppressWarnings(at_export_all(s,d,formats=c('qupath','geojson'),scope='all',progress=FALSE))
  expect_identical(rc$status,c('error','ok'))
  expect_false(file.exists(rc$path[1]));expect_true(file.exists(rc$path[2]))
  rc <- .export_receipt()
  testthat::local_mocked_bindings(.export_bundle=function(...) stop('injected receipt failure'))
  expect_warning(out <- .export_receipt_files(rc,d),'Could not publish')
  expect_s3_class(out,'tbl_df');expect_type(attr(out,'receipt_error'),'character')
})

test_that('summary generation failure does not discard completed item receipts', {
  s <- at_example_session(1); d <- withr::local_tempdir()
  testthat::local_mocked_bindings(at_manifest=function(...) stop('injected summary failure'))
  expect_warning(rc <- at_export_all(s,d,formats='csv',scope='all',progress=FALSE),'summary')
  expect_identical(rc$status,'ok')
  expect_match(attr(rc,'summary_error'),'injected summary failure')
  expect_true(file.exists(file.path(d,'_export_manifest.csv')))
})

test_that('large file receipts retain double byte counts', {
  d <- withr::local_tempdir();p <- file.path(d,'large.bin')
  # Sparse file: validates real file.info sizes without allocating gigabytes.
  writer <- function(paths) {con <- file(paths[1],'wb');on.exit(close(con));seek(con,2^31+7,origin='start');writeBin(as.raw(1),con)}
  rc <- .export_outcome(p,writer)
  expect_identical(rc$status,'ok');expect_identical(rc$bytes,2^31+8)
})

test_that('every mask split applies the same filename policy', {
  skip_if_not_installed('tiff')
  p <- at_project(tiny_image(),at_layer_add(at_layer('../layer'),at_roi_rect(1,1,3,3,'../label',id='../roi')),name='../project')
  for(per in c('project','layer','class','roi')) {
    d <- withr::local_tempdir();rc <- at_write_masks(p,d,per=per)
    expect_identical(rc$status,'ok')
    expect_true(startsWith(normalizePath(rc$path),paste0(normalizePath(d),'/')))
    expect_true(file.exists(rc$sidecar_path))
  }
})

test_that('missing staged members cannot be reported as complete', {
  d <- withr::local_tempdir(); paths <- file.path(d,c('x.tif','x.tif.legend.json'))
  rc <- .export_outcome(paths,function(p) writeLines('pixels',p[1]))
  expect_identical(rc$status,'error');expect_match(rc$message,'Incomplete export')
  expect_false(any(file.exists(paths)))
  expect_length(list.files(d,all.files=TRUE,no..=TRUE),0)
})
