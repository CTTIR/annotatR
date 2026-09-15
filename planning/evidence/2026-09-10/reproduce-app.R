# Run from the repository root. Diagnostic output is not a pass/fail test result.
pkgload::load_all('.', quiet=TRUE)
appdir <- 'inst/shiny/annotatR'
s <- at_example_session(2)
s$autosave <- FALSE
options(annotatR.session=s)
app <- withr::with_dir(appdir,source('app.R',local=new.env(parent=globalenv()))$value)
feat <- list(type='Feature',geometry=list(type='Polygon',coordinates=list(list(c(2,2),c(6,2),c(6,6),c(2,6),c(2,2)))))
cat('\nCASE: folder load while cursor already 1\n')
shiny::testServer(app, {
  session$setInputs('queue-filter'='all');session$flushReact()
  before <- rv$project$image$source
  d <- tempfile();dir.create(d);tiff::writeTIFF(matrix(1,5,5),file.path(d,'new.tif'))
  session$setInputs('data-dir'=d,'data-load'=1);session$flushReact()
  cat('manifest image:',basename(rv$session$manifest$path[1]),'live image:',basename(rv$project$image$source),'old retained:',identical(before,rv$project$image$source),'\n')
})
cat('\nCASE: undo crosses images\n')
shiny::testServer(app, {
  session$setInputs('queue-filter'='all');session$flushReact()
  first <- rv$project$image$source
  session$setInputs('canvas-canvas_created'=feat)
  session$setInputs('session-save'=1)
  session$setInputs(key_next=1)
  second <- rv$project$image$source
  cat('before undo cursor:',rv$cursor,'image:',basename(second),'history:',length(rv$undo),'\n')
  session$setInputs(key_undo=1)
  cat('after undo cursor:',rv$cursor,'image:',basename(rv$project$image$source),'is first image:',identical(first,rv$project$image$source),'\n')
})
cat('\nCASE: unsaved navigation discards edits\n')
shiny::testServer(app, {
  session$setInputs('queue-filter'='all');session$flushReact()
  initial <- nrow(at_rois(rv$project))
  session$setInputs('canvas-canvas_created'=feat)
  cat('before navigation:',nrow(at_rois(rv$project)),'\n')
  session$setInputs(key_next=1);session$setInputs(key_prev=1)
  cat('after navigation:',nrow(at_rois(rv$project)),'initial:',initial,'\n')
})
cat('\nCASE: shift-enter commit/advance\n')
shiny::testServer(app, {
  session$setInputs('queue-filter'='all');session$flushReact()
  first <- rv$project$image$source
  session$setInputs('canvas-canvas_created'=feat)
  cat('before commit live ROI count:',nrow(at_rois(rv$project)),'\n')
  session$setInputs(key_commit_advance=1);session$flushReact()
  cat('cursor:',rv$cursor,'status:',rv$session$manifest$status,'project counts:',vapply(rv$session$projects,function(p) if(is.null(p)) -1L else nrow(at_rois(p)),integer(1)),'\n')
  cat('project sources:',vapply(rv$session$projects,function(p) if(is.null(p)) 'NULL' else basename(p$image$source),character(1)),'\n')
})
cat('\nCASE: undo not autosaved\n')
s$autosave <- TRUE; options(annotatR.session=s)
shiny::testServer(app, {
  session$setInputs('queue-filter'='all');session$flushReact()
  session$setInputs('canvas-canvas_created'=feat);session$flushReact()
  session$setInputs(key_undo=1);session$flushReact()
  cat('after undo live:',nrow(at_rois(rv$project)),'saved:',nrow(at_rois(rv$session$projects[[1]])),'indicator:',rv$saved,'\n')
})
