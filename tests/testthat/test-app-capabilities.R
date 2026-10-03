skip_if_not_installed("shiny")
for (module in c("mod_state.R", "mod_canvas.R", "mod_layers.R", "mod_roitable.R")) {
  source(system.file("shiny", "annotatR", "modules", module, package="annotatR"), local=TRUE)
}
cap_state <- function() {
  s <- demo_session(2); s$autosave <- FALSE
  p <- at_project(tiny_image(), at_layer("base", labels="a"))
  p <- at_add_roi(p,"base",at_roi_point(2,2,"a"))
  rv <- shiny::reactiveValues(session=s,cursor=1L,project=p,tool="point")
  .state_init(rv); rv
}
test_that("ordinary ingress rejects unversioned counters and protects all locked content", {
  shiny::isolate({
    rv <- cap_state()
    expect_null(.state_event(rv, 1))
    rv$project$layers$base$style$locked <- TRUE
    id <- at_rois(rv$project)$roi_id
    expect_false(.state_mutate(rv,function(p) at_remove_roi(p,id)))
    expect_equal(nrow(at_rois(rv$project)),1L)
    expect_false(.state_mutate(rv,function(p) {p$layers$base$labels <- c("a","b");p}))
    rv$project$layers$base$style$locked <- FALSE
    rv$project$layers$base$rois[[1]]$attributes$locked <- TRUE
    expect_false(.state_mutate(rv,function(p) at_remove_roi(p,id)))
    expect_equal(nrow(at_rois(rv$project)),1L)
    rv$undo <- list(list(layers=list()))
    expect_false(.state_undo(rv))
    expect_equal(length(rv$undo),1L)
    to <- rv$project; to$layers$base$style$locked <- TRUE
    expect_identical(.copy_forward(rv$project,to),to)
  })
})
test_that("dirty queue replacement has a recovery snapshot even when first read fails", {
  testthat::local_mocked_bindings(showNotification=function(...) NULL, .package="shiny")
  shiny::isolate({
    rv <- cap_state()
    .state_mutate(rv,function(p) at_add_roi(p,"base",at_roi_point(4,4,"a")))
    old <- rv$project; old_id <- rv$entry_id
    rv$load_project <- function(...) stop("corrupt image")
    replacement <- demo_session(1)
    expect_true(.state_replace(rv,replacement))
    expect_null(rv$project)
    expect_false(rv$display_ready)
    expect_match(rv$display_error,"corrupt image")
    expect_false(rv$session$autosave)
    expect_true(.state_restore_queue(rv))
    expect_identical(rv$entry_id,old_id)
    expect_identical(rv$project,old)
    expect_true(rv$dirty[[old_id]])
    expect_equal(length(rv$undo),1L)
    expect_identical(rv$saved,"unsaved")
  })
})
test_that("form mutations use click payload values and original layer", {
  rv <- cap_state()
  shiny::testServer(mod_layers_server,args=list(id="layers",rv=rv),{
    event <- c(.state_stamp(rv),list(payload=list(new_layer="original")))
    session$setInputs(new_layer="later",add_layer=event)
    expect_true("original" %in% names(rv$project$layers))
    expect_false("later" %in% names(rv$project$layers))
    session$setInputs(new_label="later",add_label=c(.state_stamp(rv),list(payload=list(new_label="original-label",layer="base"))))
    expect_true("original-label" %in% rv$project$layers$base$labels)
    expect_false("later" %in% rv$project$layers$original$labels)
  })
})
test_that("canvas projection respects visibility ordering colour and both locks", {
  testthat::local_mocked_bindings(.image_data_uri=function(...) NULL)
  p <- at_project(tiny_image(),at_layer("high",labels="a",style=at_style(z=9,colour=c(a="#ff0000"),fill_alpha=.3,stroke_width=4)))
  p <- at_add_roi(p,"high",at_roi_point(3,3,"a",locked=TRUE))
  p <- at_add_layer(p,at_layer("low",labels="b",style=at_style(z=0,locked=TRUE)))
  p <- at_add_roi(p,"low",at_roi_point(2,2,"b"))
  p <- at_add_layer(p,at_layer("hidden",labels="c",style=at_style(visible=FALSE)))
  p <- at_add_roi(p,"hidden",at_roi_point(1,1,"c"))
  f <- at_canvas(p$image,p)$x$annotations$features
  expect_length(f,2)
  expect_equal(vapply(f,function(f) f$properties$layer,""),c("low","high"))
  expect_true(all(vapply(f,function(f) isTRUE(f$properties$locked),FALSE)))
  expect_equal(f[[2]]$properties$colour,"#ff0000")
  expect_equal(f[[2]]$properties$fill_alpha,.3)
  expect_equal(f[[2]]$properties$stroke_width,4)
  expect_equal(nrow(at_rois(p)),3L)
})
test_that("PNG reader and missing display encoder explain the capability", {
  reader <- .raster_read; source <- at_tile_source
  environment(reader) <- list2env(list(requireNamespace=function(package,...) package == "tiff"), parent=environment(reader))
  environment(source) <- list2env(list(requireNamespace=function(...) FALSE, .image_data_uri=function(...) NULL), parent=environment(source))
  expect_error(reader("example.png"),"PNG.*magick|magick.*PNG")
  src <- source(tiny_image())
  expect_null(src$dataUri)
  expect_match(src$displayError,"magick")
})

test_that("restoring or replacing cannot discard a second dirty queue", {
  testthat::local_mocked_bindings(showNotification=function(...) NULL,.package="shiny")
  shiny::isolate({
    rv <- cap_state(); original <- rv$project
    rv$load_project <- function(...) {p <- original; p$meta$entry_id <- NULL; p}
    .state_replace(rv,demo_session(1))
    rv$display_ready <- TRUE
    .state_mutate(rv,function(p) at_add_roi(p,"base",at_roi_point(5,5,"a")))
    current <- rv$project; recovery <- rv$recovery_queue
    expect_false(.state_restore_queue(rv))
    expect_false(.state_replace(rv,demo_session(1)))
    expect_identical(rv$project,current)
    expect_identical(rv$recovery_queue,recovery)
    expect_equal(nrow(at_rois(rv$project)),2L)
  })
})

test_that("canvas readiness and protected creation edit and erase are enforced at ingress", {
  testthat::local_mocked_bindings(.image_data_uri=function(...) NULL)
  rv <- cap_state()
  shiny::isolate({
    rv$project$layers$base$rois[[1]]$attributes$locked <- TRUE
    rv$project <- at_add_layer(rv$project,at_layer("locked",labels="b",style=at_style(locked=TRUE)))
  })
  shiny::testServer(mod_canvas_server,args=list(id="canvas",rv=rv),{
    id <- at_rois(rv$project)$roi_id
    e <- function(payload) c(.state_stamp(rv),list(payload=payload))
    session$setInputs(canvas_ready=e(list(ready=FALSE,error="decode failed")))
    session$setInputs(canvas_created=e(list(type="Feature",geometry=list(type="Point",coordinates=c(3,3)),target=list(layer="base",label="a"))))
    expect_equal(nrow(at_rois(rv$project)),1L)
    session$setInputs(canvas_ready=list(entry_id="old",revision=0,payload=list(ready=TRUE)))
    expect_false(rv$display_ready)
    session$setInputs(canvas_ready=e(list(ready=TRUE)))
    expect_true(rv$display_ready)
    session$setInputs(canvas_erased=e(id))
    session$setInputs(canvas_edited=e(list(roi_id=id,geometry=list(type="Point",coordinates=c(6,6)))))
    session$setInputs(canvas_created=e(list(type="Feature",geometry=list(type="Point",coordinates=c(3,3)),target=list(layer="locked",label="b"))))
    expect_equal(nrow(at_rois(rv$project)),1L)
    expect_equal(unname(sf::st_coordinates(rv$project$layers$base$rois[[1]]$geometry)),matrix(c(2,2),1,2),ignore_attr=TRUE)
    expect_equal(rv$revision,0)
    expect_length(rv$undo,0)
  })
})

test_that("radio remount selection cannot reset the active label", {
  rv <- cap_state()
  shiny::isolate({rv$project$layers$base$labels <- c("a","b");rv$active_label <- "b"})
  shiny::testServer(mod_layers_server,args=list(id="layers",rv=rv),{
    session$setInputs(layer_intent=c(.state_stamp(rv),list(payload=list(value="base"))))
    expect_identical(rv$active_label,"b")
  })
})

test_that("malformed form payloads are rejected before field lookup", {
  rv <- cap_state()
  shiny::isolate({
    for (payload in list(1, list(new_layer=c("a","b")), list(new_layer=NA_character_), list())) {
      expect_null(.state_event(rv,c(.state_stamp(rv),list(payload=payload)),fields="new_layer"))
    }
  })
})

test_that("display-origin save rejects unseen entries but current failed display can save retained annotations", {
  shiny::isolate({
    rv <- cap_state(); displayed <- .state_stamp(rv)
    project <- at_project(tiny_image(),at_layer("base",labels="a"))
    project <- at_add_roi(project,"base",at_roi_point(4,4,"a"))
    rv$cursor <- 2L; .state_adopt(rv,project)
    rv$display_ready <- FALSE
    attempts <- 0L
    rv$save_callback <- function(candidate,cursor) { attempts <<- attempts+1L; candidate }
    expect_false(.state_save(rv,complete=TRUE,event=displayed))
    expect_false(.state_status(rv,"flagged",event=displayed))
    expect_equal(attempts,0L)
    expect_identical(rv$session$manifest$status[2],"pending")
    expect_true(.state_save(rv,event=.state_stamp(rv)))
    expect_equal(attempts,1L)
    expect_identical(rv$saved,"saved")
    expect_equal(nrow(at_rois(rv$session$projects[[2]])),1L)
  })
})
