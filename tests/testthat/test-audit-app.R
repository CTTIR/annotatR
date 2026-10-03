skip_if_not_installed("shiny")
skip_if_not_installed("bslib")
skip_if_not_installed("shinyjs")
skip_if_not_installed("tiff")

audit_app <- function(autosave=FALSE, env=parent.frame()) {
  dir <- tempfile(); dir.create(dir)
  withr::defer(unlink(dir,recursive=TRUE),envir=env)
  paths <- file.path(dir,c("first.tif","second.tif"))
  for (i in seq_along(paths)) tiff::writeTIFF(matrix(i-1,10,10),paths[i])
  s <- at_session(paths,labels="a",out_dir=file.path(dir,"annotations"))
  s$autosave <- autosave
  withr::local_options(list(annotatR.session=s),.local_envir=env)
  appdir <- system.file("shiny","annotatR",package="annotatR")
  withr::with_dir(appdir,source("app.R",local=new.env(parent=globalenv()))$value)
}

audit_feature <- list(type="Feature",geometry=list(type="Polygon",coordinates=list(
  list(c(2,2),c(6,2),c(6,6),c(2,6),c(2,2)))))

# Test ingress mirrors the identity and target displayed by the browser.
audit_event <- function(rv, payload) {
  # State/ingress tests simulate a ready display; Chromium covers the decode handshake.
  if (!is.null(rv$project)) rv$display_ready <- TRUE
  if (is.list(payload) && identical(payload$type, "Feature")) {
    payload$target <- list(layer = rv$active_layer, label = rv$active_label)
  }
  list(entry_id = rv$entry_id, revision = rv$revision, payload = payload)
}

test_that("A02 commit advance stores the edited project in its own queue slot", {
  app <- audit_app()
  shiny::testServer(app, {
    session$setInputs(`queue-filter`="all"); session$flushReact()
    first <- rv$project$image$source
    session$setInputs(`canvas-canvas_created`=audit_event(rv, audit_feature))
    session$setInputs(key_commit_advance=audit_event(rv, 1)); session$flushReact()
    expect_equal(rv$cursor,2L)
    expect_equal(if (is.null(rv$session$projects[[1]])) 0L else
      nrow(at_rois(rv$session$projects[[1]])),1L)
    expect_identical(rv$session$projects[[1]]$image$source,first)
    expect_identical(rv$project$image$source,rv$session$manifest$path[2])
    expect_false(identical(rv$session$projects[[2]]$image$source,first))
  })
})

test_that("A03 undo history cannot cross queue entries", {
  app <- audit_app()
  shiny::testServer(app, {
    session$setInputs(`queue-filter`="all"); session$flushReact()
    session$setInputs(`canvas-canvas_created`=audit_event(rv, audit_feature))
    session$setInputs(`session-save`=audit_event(rv, list()))
    session$setInputs(key_next=audit_event(rv, 1))
    second <- rv$project$image$source
    session$setInputs(key_undo=audit_event(rv, 1))
    expect_equal(rv$cursor,2L)
    expect_identical(rv$project$image$source,second)
    expect_identical(rv$project$image$source,rv$session$manifest$path[2])
  })
})

test_that("A04 replacing a folder refreshes the project when cursor stays one", {
  app <- audit_app()
  dir <- tempfile(); dir.create(dir); withr::defer(unlink(dir,recursive=TRUE))
  tiff::writeTIFF(matrix(1,5,5),file.path(dir,"new.tif"))
  shiny::testServer(app, {
    session$setInputs(`queue-filter`="all"); session$flushReact()
    session$setInputs(`data-dir`=dir,`data-load`=audit_event(rv, list(dir=dir))); session$flushReact()
    expect_equal(rv$cursor,1L)
    expect_identical(basename(rv$session$manifest$path[1]),"new.tif")
    expect_identical(rv$project$image$source,rv$session$manifest$path[1])
  })
})

test_that("A11 autosaved undo keeps persisted state and saved indicator truthful", {
  app <- audit_app(autosave=TRUE)
  shiny::testServer(app, {
    session$setInputs(`queue-filter`="all"); session$flushReact()
    session$setInputs(`canvas-canvas_created`=audit_event(rv, audit_feature)); session$flushReact()
    session$setInputs(key_undo=audit_event(rv, 1)); session$flushReact()
    expect_equal(nrow(at_rois(rv$project)),0L)
    # Autosave completion may be asynchronous, but saved must never be false evidence.
    if (identical(rv$saved,"saved")) {
      expect_equal(nrow(at_rois(rv$session$projects[[1]])),0L)
      saved <- at_load_session(file.path(rv$session$out_dir,"_session.rds"))
      expect_equal(nrow(at_rois(saved$projects[[1]])),0L)
    }
  })
})

test_that("A12 navigation retains in-session edits with autosave off", {
  app <- audit_app()
  shiny::testServer(app, {
    session$setInputs(`queue-filter`="all"); session$flushReact()
    session$setInputs(`canvas-canvas_created`=audit_event(rv, audit_feature))
    expect_equal(nrow(at_rois(rv$project)),1L)
    id <- at_rois(rv$project)$roi_id
    session$setInputs(key_next=audit_event(rv, 1)); session$setInputs(key_prev=audit_event(rv, 1))
    expect_equal(nrow(at_rois(rv$project)),1L)
    expect_identical(at_rois(rv$project)$roi_id,id)
  })
})

for (autosave in c(FALSE, TRUE)) local({
  enabled <- autosave
  test_that(paste("T02 commit failure retains original entry, autosave", enabled), {
    app <- audit_app(autosave = enabled)
    shiny::testServer(app, {
      session$setInputs(`queue-filter` = "all"); session$flushReact()
      session$setInputs(`canvas-canvas_created` = audit_event(rv, audit_feature))
      original <- rv$project
      # Exercise the real save callback with an unwritable destination.
      good_dir <- rv$session$out_dir
      attempts <- 0L
      writer <- rv$save_callback
      rv$save_callback <- function(candidate, cursor) {
        attempts <<- attempts + 1L
        writer(candidate, cursor)
      }
      bad <- tempfile(); writeLines("file, not directory", bad)
      rv$session$out_dir <- bad
      session$setInputs(key_commit_advance = audit_event(rv, 1)); session$flushReact()
      expect_equal(rv$cursor, 1L)
      expect_false(rv$session$manifest$status[1] == "complete")
      expect_identical(rv$project, original)
      expect_identical(rv$saved, "unsaved")
      expect_match(rv$save_error, "Save failed")
      expect_identical(rv$session$projects[[1]], original)
      session$flushReact()
      expect_equal(attempts, 1L)
      rv$session$out_dir <- good_dir
      session$setInputs(key_commit_advance = audit_event(rv, 2))
      expect_equal(attempts, 2L)
      expect_equal(rv$cursor, 2L)
      expect_identical(rv$session$manifest$status[1], "complete")
      expect_identical(rv$session$projects[[1]], original)
      expect_null(rv$save_error)
      unlink(bad)
    })
  })

  test_that(paste("T02 modern events reject stale identity and revision, autosave", enabled), {
    app <- audit_app(autosave = enabled)
    shiny::testServer(app, {
      session$setInputs(`queue-filter` = "all"); session$flushReact()
      event <- list(entry_id = rv$project$meta$entry_id, revision = 0,
                    payload = audit_event(rv, audit_feature)$payload)
      session$setInputs(`canvas-canvas_created` = event)
      expect_equal(nrow(at_rois(rv$project)), 1L)
      expect_equal(rv$revision, 1)
      # Change the payload so input deduplication cannot hide a stale-event bug.
      event$payload$properties <- list(replay = "stale revision")
      session$setInputs(`canvas-canvas_created` = event)
      expect_equal(nrow(at_rois(rv$project)), 1L)
      session$setInputs(key_next = audit_event(rv, 1))
      event$payload$properties <- list(replay = "previous image")
      session$setInputs(`canvas-canvas_created` = event)
      expect_equal(nrow(at_rois(rv$project)), 0L)
      session$setInputs(key_prev = audit_event(rv, 1))
      session$setInputs(key_undo = audit_event(rv, 1))
      expect_equal(rv$revision, 2)
      expect_equal(nrow(at_rois(rv$project)), 0L)
      session$setInputs(key_redo = audit_event(rv, 1))
      expect_equal(rv$revision, 3)
      expect_equal(rv$project$meta$annotation_revision, 3)
      expect_equal(nrow(at_rois(rv$project)), 1L)
      expect_identical(rv$saved, if (enabled) "saved" else "unsaved")
      # Direct widget events are forbidden, including after valid envelopes.
      session$setInputs(`canvas-canvas_created` = audit_feature)
      expect_equal(nrow(at_rois(rv$project)), 1L)
    })
  })
})

test_that("T02 queue replacement preserves autosave and resets annotation history", {
  app <- audit_app()
  dir <- tempfile(); dir.create(dir); withr::defer(unlink(dir, recursive = TRUE))
  tiff::writeTIFF(matrix(1, 5, 5), file.path(dir, "new.tif"))
  shiny::testServer(app, {
    session$setInputs(`queue-filter` = "all"); session$flushReact()
    session$setInputs(`canvas-canvas_created` = audit_event(rv, audit_feature))
    old_generation <- rv$session_generation
    session$setInputs(`data-dir` = dir, `data-load`=audit_event(rv, list(dir=dir)))
    expect_false(rv$session$autosave)
    expect_equal(rv$session_generation, old_generation + 1)
    session$setInputs(key_undo = audit_event(rv, 1))
    expect_equal(nrow(at_rois(rv$project)), 0L)
    expect_identical(rv$entry_id, rv$session$manifest$entry_id[1])
  })
})

test_that("T02 annotation history is bounded, excludes pixels and preserves edit IDs", {
  app <- audit_app()
  shiny::testServer(app, {
    session$setInputs(`queue-filter` = "all"); session$flushReact()
    rv$history_limit <- 2L
    for (i in 1:4) session$setInputs(`canvas-canvas_created` = audit_event(rv, audit_feature))
    expect_length(rv$undo, 2L)
    expect_true(all(vapply(rv$undo, function(x) identical(names(x), "layers"), logical(1))))
    roi_id <- at_rois(rv$project)$roi_id[1]
    session$setInputs(`canvas-canvas_edited` = audit_event(rv, list(roi_id = roi_id,
      geometry = audit_feature$geometry, layer = "annotations", label = "a")))
    expect_true(roi_id %in% at_rois(rv$project)$roi_id)
    expect_equal(nrow(at_rois(rv$project)), 4L)
    session$setInputs(key_undo = audit_event(rv, 1))
    session$setInputs(`layers-new_layer` = "custom", `layers-add_layer` = audit_event(rv, list(new_layer="custom")))
    expect_length(rv$redo, 0L)
    expect_identical(rv$saved, "unsaved")
    session$setInputs(key_undo = audit_event(rv, 2))
    expect_false("custom" %in% names(rv$project$layers))
  })
})

test_that("T02 restored projects start at their persisted annotation revision", {
  app <- audit_app()
  s <- getOption("annotatR.session")
  s$projects[[1]] <- at_project(at_read_image(s$manifest$path[1]),
    at_layer("annotations", labels = "a"), entry_id = s$manifest$entry_id[1],
    annotation_revision = 41)
  withr::local_options(annotatR.session = s)
  shiny::testServer(app, {
    session$setInputs(`queue-filter` = "all"); session$flushReact()
    expect_equal(rv$revision, 41)
    session$setInputs(`canvas-canvas_created` = audit_event(rv, audit_feature))
    expect_equal(rv$revision, 42)
    session$setInputs(key_undo = audit_event(rv, 1))
    expect_equal(rv$revision, 43)
  })
})

for (autosave in c(FALSE, TRUE)) local({
  enabled <- autosave
  test_that(paste("T02 commit persists completion before advancing, autosave", enabled), {
    app <- audit_app(autosave = enabled)
    shiny::testServer(app, {
      session$setInputs(`queue-filter` = "all"); session$flushReact()
      session$setInputs(`canvas-canvas_created` = audit_event(rv, audit_feature))
      first_id <- rv$entry_id
      session$setInputs(key_commit_advance = list(entry_id = first_id,
        revision = rv$revision, payload = 1))
      disk <- at_load_session(file.path(rv$session$out_dir, "_session.rds"))
      expect_identical(disk$projects[[1]]$meta$entry_id, first_id)
      expect_equal(nrow(at_rois(disk$projects[[1]])), 1L)
      expect_identical(disk$manifest$status, c("complete", "pending"))
      expect_equal(disk$cursor, 1L)
      expect_equal(rv$cursor, 2L)
      expect_equal(nrow(at_rois(rv$project)), 0L)
      expect_identical(rv$entry_id, rv$session$manifest$entry_id[2])
    })
  })
})

test_that("T02 stale edits, erase, keyboard navigation and partial envelopes are rejected", {
  app <- audit_app()
  shiny::testServer(app, {
    session$setInputs(`queue-filter` = "all"); session$flushReact()
    session$setInputs(`canvas-canvas_created` = audit_event(rv, audit_feature))
    stale <- list(entry_id = rv$entry_id, revision = 0, payload = 1)
    session$setInputs(key_next = stale)
    expect_equal(rv$cursor, 1L)
    id <- at_rois(rv$project)$roi_id[1]
    session$setInputs(`canvas-canvas_erased` = list(entry_id = rv$entry_id,
      revision = 0, payload = id))
    session$setInputs(`canvas-canvas_edited` = list(entry_id = rv$entry_id,
      revision = 0, payload = list(roi_id = id, geometry = audit_feature$geometry)))
    session$setInputs(`canvas-canvas_created` = list(entry_id = rv$entry_id,
      payload = audit_feature))
    expect_equal(nrow(at_rois(rv$project)), 1L)
    expect_equal(rv$revision, 1)
    session$setInputs(`canvas-canvas_erased` = list(entry_id = rv$entry_id,
      revision = 1, payload = id))
    expect_equal(nrow(at_rois(rv$project)), 0L)
    session$setInputs(key_undo = audit_event(rv, 1))
    expect_identical(at_rois(rv$project)$roi_id, id)
    session$setInputs(`roitable-del_id` = id, `roitable-delete` = audit_event(rv, list(del_id=id)))
    expect_length(rv$redo, 0L)
    session$setInputs(key_undo = audit_event(rv, 2))
    expect_identical(at_rois(rv$project)$roi_id, id)
    session$setInputs(`layers-new_label` = "new", `layers-add_label` = audit_event(rv, list(new_label="new", layer=rv$active_layer)))
    expect_length(rv$redo, 0L)
    expect_true("new" %in% rv$project$layers$annotations$labels)
    session$setInputs(key_undo = audit_event(rv, 3))
    expect_false("new" %in% rv$project$layers$annotations$labels)
  })
})

test_that("T02 a failed read runs once per navigation and permits recovery", {
  app <- audit_app()
  shiny::testServer(app, {
    session$setInputs(`queue-filter` = "all"); session$flushReact()
    calls <- 0L
    loader <- rv$load_project
    rv$load_project <- function(s, i) {
      calls <<- calls + 1L
      if (i == 2L) stop("Synthetic unavailable image")
      loader(s, i)
    }
    session$setInputs(`canvas-canvas_created` = audit_event(rv, audit_feature))
    rv$session$meta$note <- "Metadata does not trigger a reload"
    session$flushReact()
    expect_equal(calls, 0L)
    session$setInputs(key_next = audit_event(rv, 1)); session$flushReact()
    expect_equal(calls, 1L)
    expect_null(rv$project)
    expect_identical(rv$session$manifest$status[2], "skipped")
    session$setInputs(key_prev = audit_event(rv, 1)); session$flushReact()
    expect_equal(rv$cursor, 1L)
    expect_equal(calls, 2L)
    expect_identical(rv$project$image$source, rv$session$manifest$path[1])
  })
})

test_that('T03 failed checkpoint publication preserves prior files and completion state', {
  app <- audit_app()
  shiny::testServer(app, {
    session$setInputs(`queue-filter`='all'); session$flushReact()
    session$setInputs(`session-save`=audit_event(rv, list()))
    manifest <- file.path(rv$session$out_dir,'_session.rds')
    prior <- readRDS(manifest)
    project_path <- prior$manifest$project_path[1]
    session$setInputs(`canvas-canvas_created`=audit_event(rv, audit_feature))
    original <- rv$save_callback
    rv$save_callback <- function(candidate,cursor) {
      annotatR:::.save_checkpoint(candidate,cursor,write=function(object,path,overwrite=FALSE) {
        if (basename(path)=='_session.rds') stop('injected manifest failure')
        annotatR:::.atomic_save_rds(object,path,overwrite=overwrite)
      })
    }
    session$setInputs(`session-complete`=audit_event(rv, list()))
    expect_identical(rv$saved,'unsaved')
    expect_false(rv$session$manifest$status[1]=='complete')
    expect_identical(readRDS(manifest),prior)
    expect_equal(nrow(at_rois(at_load_project(project_path))),0L)
    expect_equal(nrow(at_rois(rv$project)),1L)
    rv$save_callback <- original
    session$setInputs(`session-complete`=audit_event(rv, list()))
    expect_identical(rv$saved,'saved')
    expect_identical(rv$session$manifest$status[1],'complete')
  })
})

test_that('T03 loading another folder preserves the old session checkpoint', {
  app <- audit_app()
  dir <- withr::local_tempdir(); tiff::writeTIFF(matrix(1,3,3),file.path(dir,'other.tif'))
  shiny::testServer(app, {
    session$setInputs(`queue-filter`='all'); session$flushReact()
    session$setInputs(`session-save`=audit_event(rv, list()))
    path <- file.path(rv$session$out_dir,'_session.rds'); prior <- readRDS(path)
    session$setInputs(`data-dir`=dir,`data-load`=audit_event(rv, list(dir=dir))); session$flushReact()
    session$setInputs(`session-save`=audit_event(rv, list()))
    expect_false(identical(path,file.path(rv$session$out_dir,'_session.rds')))
    expect_identical(readRDS(path),prior)
  })
})
