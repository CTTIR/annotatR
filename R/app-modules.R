# Shiny modules of the annotation app. All app code lives in R/ so the app can
# be built and tested as an object (at_app()) without sourcing files from
# inst/; inst/ only holds static assets. Every module receives the shared
# reactiveValues `rv` documented in app-builder.R. Internal.

# ---- Shared transitions ------------------------------------------------------

# Replace the current project after a user edit: push undo history, mark the
# state unsaved and tell an attached control hub. Refused in read-only mode.
.app_edit <- function(rv, project, action = "edit") {
  if (isTRUE(rv$read_only)) {
    shiny::showNotification("This session is read-only; the edit was not applied.",
                            type = "warning")
    return(invisible(FALSE))
  }
  rv$undo <- c(rv$undo, list(rv$project))
  rv$redo <- list()
  rv$project <- project
  rv$saved <- "unsaved"
  rv$last_action <- action
  invisible(TRUE)
}

# ---- Queue -------------------------------------------------------------------

.status_glyph <- function(status) {
  c(pending = "\u25cb", in_progress = "\u25d0", complete = "\u2713",
    flagged = "\u2691", skipped = "\u2298")[status]
}

mod_queue_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::div(
      class = "at-queue-controls",
      shiny::selectInput(ns("filter"), NULL,
                         choices = c("all", "pending", "in_progress", "complete", "flagged", "skipped"),
                         selected = "all"),
      shiny::actionButton(ns("prev"), "\u25c0", `aria-label` = "previous image"),
      shiny::actionButton(ns("nxt"), "\u25b6", `aria-label` = "next image"),
      shiny::actionButton(ns("next_pending"), "Next pending")
    ),
    shiny::tableOutput(ns("list")),
    shiny::div(class = "at-progress", shiny::textOutput(ns("progress")))
  )
}

mod_queue_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    shiny::observeEvent(input$nxt, {
      rv$session <- at_next(rv$session)
      rv$cursor <- rv$session$cursor
    })
    shiny::observeEvent(input$prev, {
      rv$session <- at_prev(rv$session)
      rv$cursor <- rv$session$cursor
    })
    shiny::observeEvent(input$next_pending, {
      m <- at_session_status(rv$session)
      pending <- which(m$status == "pending")
      nxt <- pending[pending > rv$cursor]
      target <- if (length(nxt)) nxt[1] else if (length(pending)) pending[1] else rv$cursor
      rv$session <- at_goto(rv$session, target)
      rv$cursor <- target
    })
    output$list <- shiny::renderTable({
      m <- at_session_status(rv$session)
      n <- m$n_rois
      # Live count for the image being edited (manifest counts only update on save).
      if (!is.null(rv$project) && rv$cursor >= 1L && rv$cursor <= length(n)) {
        n[rv$cursor] <- nrow(at_rois(rv$project))
      }
      keep <- if (input$filter != "all") m$status == input$filter else rep(TRUE, nrow(m))
      data.frame(idx = m$idx[keep], name = m$name[keep],
                 status = .status_glyph(m$status[keep]), n = n[keep])
    })
    output$progress <- shiny::renderText({
      m <- at_session_status(rv$session)
      sprintf("%d / %d complete", sum(m$status == "complete"), nrow(m))
    })
    # Keep the queue status current even while another page is in front.
    shiny::outputOptions(output, "list", suspendWhenHidden = FALSE)
    shiny::outputOptions(output, "progress", suspendWhenHidden = FALSE)
  })
}

# ---- Layers and labels ---------------------------------------------------------

.at_label_palette <- c("#e69f00", "#56b4e9", "#009e73", "#f0e442",
                       "#0072b2", "#d55e00", "#cc79a7", "#999999")

mod_layers_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Layers"),
    shiny::uiOutput(ns("layer_sel")),
    shiny::div(
      class = "at-add-row",
      shiny::textInput(ns("new_layer"), NULL, placeholder = "new layer name"),
      shiny::actionButton(ns("add_layer"), "+ layer")
    ),
    shiny::h5("Labels"),
    shiny::uiOutput(ns("label_sel")),
    shiny::div(
      class = "at-add-row",
      shiny::textInput(ns("new_label"), NULL, placeholder = "new label name"),
      shiny::actionButton(ns("add_label"), "+ label")
    )
  )
}

mod_layers_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    output$layer_sel <- shiny::renderUI({
      shiny::req(rv$project)
      shiny::radioButtons(session$ns("layer"), NULL,
                          choices = names(rv$project$layers),
                          selected = rv$active_layer)
    })
    output$label_sel <- shiny::renderUI({
      shiny::req(rv$project, rv$active_layer)
      lyr <- rv$project$layers[[rv$active_layer]]
      labs <- lyr$labels
      if (length(labs) == 0L) {
        return(shiny::div(class = "at-progress", "No labels yet \u2014 add one below."))
      }
      shiny::radioButtons(session$ns("label"), NULL, choices = labs,
                          selected = rv$active_label)
    })
    shiny::observeEvent(input$layer, {
      rv$active_layer <- input$layer
      labs <- rv$project$layers[[input$layer]]$labels
      rv$active_label <- if (length(labs)) labs[1] else NULL
    })
    shiny::observeEvent(input$label, {
      rv$active_label <- input$label
    })
    shiny::observeEvent(input$add_layer, {
      shiny::req(rv$project)
      nm <- trimws(input$new_layer %||% "")
      if (nzchar(nm) && !(nm %in% names(rv$project$layers))) {
        if (.app_edit(rv, at_add_layer(rv$project, at_layer(nm, labels = nm)), "add_layer")) {
          rv$active_layer <- nm
          rv$active_label <- nm
        }
        shiny::updateTextInput(session, "new_layer", value = "")
      }
    })
    shiny::observeEvent(input$add_label, {
      shiny::req(rv$project, rv$active_layer)
      new_lab <- trimws(input$new_label %||% "")
      if (!nzchar(new_lab)) return()
      proj <- rv$project
      lyr <- proj$layers[[rv$active_layer]]
      if (!(new_lab %in% lyr$labels)) {
        lyr$labels <- c(lyr$labels, new_lab)
        cols <- lyr$style$colour
        if (is.null(cols)) cols <- character(0)
        if (!(new_lab %in% names(cols))) {
          cols[new_lab] <- .at_label_palette[(length(cols) %% length(.at_label_palette)) + 1L]
        }
        lyr$style$colour <- cols
        proj$layers[[rv$active_layer]] <- lyr
        if (.app_edit(rv, proj, "add_label")) rv$active_label <- new_lab
        shiny::updateTextInput(session, "new_label", value = "")
      }
    })
  })
}

# ---- Canvas -----------------------------------------------------------------------

.canvas_tools <- c("pan", "rect", "polygon", "freehand", "circle", "point", "edit", "erase",
                   "probe", "select")
.read_only_tools <- c("pan", "probe", "select")

mod_canvas_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::div(
      class = "at-toolbar", role = "toolbar", `aria-label` = "drawing tools",
      lapply(.canvas_tools, function(t) shiny::actionButton(ns(paste0("tool_", t)), t))
    ),
    atCanvasOutput(ns("canvas"), height = "620px")
  )
}

# Turn a drawn GeoJSON feature (level-0 pixels) into an annot_roi.
.feature_to_roi <- function(feature, label, level = 0L) {
  at_roi_from_geojson(feature, label = label, level = level)
}

# Copy every ROI of `from` into `to` as fresh, editable ROIs (new ids,
# source = "copied"). This powers the Shift+V copy-forward throughput feature.
.copy_forward <- function(from, to) {
  for (nm in names(from$layers)) {
    if (!(nm %in% names(to$layers))) {
      to <- at_add_layer(to, at_layer(nm, labels = from$layers[[nm]]$labels))
    }
    for (r in from$layers[[nm]]$rois) {
      cp <- at_roi_from_sf(r$geometry, label = r$label, level = r$level, source = "copied")
      to <- at_add_roi(to, nm, cp)
    }
  }
  to
}

mod_canvas_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    proxy <- at_canvas_proxy("canvas", session = session)
    # Render on image / ROI / tool / band-view change. The widget caches the base
    # image by data URI and keeps the viewport, so an ROI edit is a cheap redraw.
    output$canvas <- renderAtCanvas({
      shiny::req(rv$project)
      at_canvas(rv$project$image, project = rv$project, tool = rv$tool %||% "pan",
                view = rv$view, options = list(selection = as.list(rv$selection %||% character())))
    })

    shiny::observeEvent(rv$tool, {
      for (t in .canvas_tools) {
        shinyjs::toggleClass(id = paste0("tool_", t), class = "active",
                             condition = identical(rv$tool, t))
      }
    }, ignoreInit = FALSE)

    for (t in .canvas_tools) {
      local({
        tool <- t
        shiny::observeEvent(input[[paste0("tool_", tool)]], {
          if (isTRUE(rv$read_only) && !tool %in% .read_only_tools) {
            shiny::showNotification("Read-only session: drawing tools are disabled.", type = "warning")
            return()
          }
          rv$tool <- tool
        })
      })
    }

    shiny::observeEvent(input$canvas_created, {
      shiny::req(rv$project)
      layer <- rv$active_layer %||% names(rv$project$layers)[1]
      label <- rv$active_label %||% (rv$project$layers[[layer]]$labels[1] %||% "unlabelled")
      if (isTRUE(rv$project$layers[[layer]]$style$locked)) {
        shiny::showNotification(paste("Layer", layer, "is locked."), type = "warning")
        return()
      }
      roi <- tryCatch(.feature_to_roi(input$canvas_created, label), error = function(e) e)
      if (inherits(roi, "error")) {
        shiny::showNotification(paste("Could not add ROI:", conditionMessage(roi)), type = "warning")
        return()
      }
      .app_edit(rv, at_add_roi(rv$project, layer, roi), "draw")
    })

    shiny::observeEvent(input$canvas_erased, {
      shiny::req(rv$project, input$canvas_erased)
      .app_edit(rv, at_remove_roi(rv$project, input$canvas_erased), "erase")
    })

    shiny::observeEvent(input$canvas_edited, {
      ed <- input$canvas_edited
      shiny::req(rv$project, ed$roi_id, ed$geometry)
      roi <- tryCatch(.feature_to_roi(list(type = "Feature", geometry = ed$geometry,
                                           properties = list()),
                                      ed$label %||% "unlabelled"),
                      error = function(e) e)
      if (inherits(roi, "error")) {
        shiny::showNotification(paste("Edit failed:", conditionMessage(roi)), type = "warning")
        return()
      }
      old <- .find_roi(rv$project, ed$roi_id)
      if (!is.null(old)) {
        roi$id <- old$roi$id
        roi$attributes <- old$roi$attributes
        roi$created <- old$roi$created
      }
      proj <- at_remove_roi(rv$project, ed$roi_id)
      proj <- at_add_roi(proj, ed$layer %||% names(proj$layers)[1], roi)
      .app_edit(rv, proj, "edit")
    })

    shiny::observeEvent(input$canvas_probed, {
      p <- input$canvas_probed
      rv$probe <- c(x = as.numeric(p$x), y = as.numeric(p$y))
    })
    shiny::observeEvent(input$canvas_selected, {
      rv$selection <- as.character(unlist(input$canvas_selected))
    }, ignoreNULL = FALSE)
    shiny::observeEvent(input$canvas_viewport, {
      b <- unlist(input$canvas_viewport$bounds)
      if (length(b) == 4L) rv$viewport <- as.numeric(b)
    })

    shiny::observeEvent(rv$selection, {
      at_canvas_set_selection(proxy, as.character(rv$selection %||% character()))
    }, ignoreNULL = FALSE, ignoreInit = TRUE)
    shiny::observeEvent(rv$fit_bounds, {
      at_canvas_fit(proxy, rv$fit_bounds)
    }, ignoreInit = TRUE)
    shiny::observeEvent(list(rv$overlay_on, rv$project, rv$mask_type, rv$overlap), {
      if (isTRUE(rv$overlay_on) && !is.null(rv$project)) {
        m <- tryCatch(.current_mask(rv), error = function(e) NULL)
        if (!is.null(m)) at_canvas_set_overlay(proxy, m, alpha = rv$overlay_alpha %||% 0.5)
      } else {
        .canvas_msg(proxy, "clear_overlay", list())
      }
    }, ignoreInit = TRUE)

    shiny::observeEvent(rv$paste_forward, {
      shiny::req(rv$project, rv$cursor > 1L)
      prev <- rv$session$projects[[rv$cursor - 1L]]
      shiny::req(prev)
      .app_edit(rv, .copy_forward(prev, rv$project), "paste_forward")
    }, ignoreInit = TRUE)
  })
}

# ---- Mask -----------------------------------------------------------------------------

mod_mask_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Mask preview"),
    shiny::radioButtons(ns("type"), NULL,
                        choices = c("binary", "labelled", "multiclass"),
                        selected = "labelled", inline = TRUE),
    shiny::selectInput(ns("overlap"), "Overlap",
                       choices = c("last", "first", "max", "min")),
    shiny::checkboxInput(ns("overlay"), "Show mask overlay on the canvas", FALSE),
    shiny::plotOutput(ns("preview"), height = "200px"),
    shiny::uiOutput(ns("overlap_warn")),
    shiny::tableOutput(ns("stats")),
    shiny::actionButton(ns("export"), "Export this mask")
  )
}

# Build the current mask.
.current_mask <- function(rv) {
  shiny::req(rv$project)
  at_mask(rv$project, type = rv$mask_type %||% "labelled",
          overlap = rv$overlap %||% "last")
}

mod_mask_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    shiny::observeEvent(input$type, rv$mask_type <- input$type)
    shiny::observeEvent(input$overlap, rv$overlap <- input$overlap)
    shiny::observeEvent(input$overlay, rv$overlay_on <- isTRUE(input$overlay), ignoreInit = TRUE)
    output$preview <- shiny::renderPlot({
      m <- tryCatch(.current_mask(rv), error = function(e) e)
      if (inherits(m, "error")) {
        graphics::plot.new()
        graphics::text(0.5, 0.5, paste("Mask unavailable:", conditionMessage(m)), cex = 0.9)
        return(invisible())
      }
      at_plot_mask(at_mask_preview(m, max_dim = 400L))
    })
    output$stats <- shiny::renderTable({
      m <- tryCatch(.current_mask(rv), error = function(e) NULL)
      if (is.null(m)) return(NULL)
      st <- at_mask_stats(m)
      st[, c("label", "n_px", "frac_total")]
    })
    output$overlap_warn <- shiny::renderUI({
      shiny::req(rv$project)
      ov <- at_rois_overlap(rv$project$layers[[rv$active_layer %||% names(rv$project$layers)[1]]])
      if (nrow(ov) > 0L) {
        shiny::span(class = "at-warn", "\u26a0 overlapping ROIs")
      }
    })
    shiny::observeEvent(input$export, {
      shiny::req(rv$project)
      dir <- file.path(rv$session$out_dir, "masks")
      if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
      name <- .safe_component(at_session_status(rv$session)$name[rv$cursor])
      at_write_mask(.current_mask(rv), file.path(dir, paste0(name, ".tif")), overwrite = TRUE)
    })
  })
}

# ---- ROI table ----------------------------------------------------------------------

mod_roitable_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("ROIs"),
    shiny::tableOutput(ns("table")),
    shiny::textInput(ns("del_id"), NULL, placeholder = "roi_id to delete or select"),
    shiny::actionButton(ns("select"), "Select ROI"),
    shiny::actionButton(ns("delete"), "Delete ROI")
  )
}

mod_roitable_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    output$table <- shiny::renderTable({
      shiny::req(rv$project)
      rt <- at_rois(rv$project)
      if (nrow(rt) == 0L) {
        return(data.frame(roi_id = character(0), layer = character(0),
                          label = character(0), area_px = double(0), review = character(0)))
      }
      review <- vapply(rt$roi_id, function(id) {
        hit <- .find_roi(rv$project, id)
        hit$roi$attributes$review_status %||% "unreviewed"
      }, character(1))
      data.frame(roi_id = rt$roi_id, layer = rt$layer, label = rt$label,
                 area_px = round(rt$area_px, 1), review = unname(review))
    })
    shiny::observeEvent(input$delete, {
      shiny::req(rv$project, nzchar(input$del_id))
      .app_edit(rv, at_remove_roi(rv$project, input$del_id), "delete")
    })
    shiny::observeEvent(input$select, {
      shiny::req(rv$project, nzchar(input$del_id))
      rv$selection <- input$del_id
    })
  })
}

# ---- Export -------------------------------------------------------------------------

mod_export_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Export"),
    shiny::checkboxGroupInput(ns("formats"), "Formats",
                              choices = c("mask_tiff", "geojson", "qupath", "csv"),
                              selected = c("mask_tiff", "geojson")),
    shiny::selectInput(ns("scope"), "Scope",
                       choices = c("current", "complete", "all", "flagged")),
    shiny::downloadButton(ns("run"), "Export & download", class = "btn-primary"),
    shiny::helpText("Downloads a .zip; a copy is also written to the session's export folder."),
    shiny::tableOutput(ns("receipt")),
    shiny::hr(),
    shiny::h5("qupflowR handoff"),
    shiny::helpText("Writes a neutral, SHA-256-inventoried handoff directory (QuPath GeoJSON,",
                    "masks with legends, manifest) under the session's export folder."),
    shiny::textInput(ns("handoff_name"), NULL, placeholder = "handoff folder name"),
    shiny::actionButton(ns("handoff"), "Write handoff"),
    shiny::downloadButton(ns("handoff_zip"), "Download handoff (.zip)"),
    shiny::verbatimTextOutput(ns("handoff_status"))
  )
}

# Images to export for a given scope.
.export_targets <- function(rv, scope) {
  st <- at_session_status(rv$session)
  switch(scope,
         current  = rv$cursor,
         complete = which(st$status == "complete"),
         flagged  = which(st$status == "flagged"),
         all      = seq_len(nrow(st)))
}

# Write the selected formats for every in-scope annotated image into `dir`.
# Returns a receipt data.frame (image, format, path); skipped/failed image
# names are carried as attributes. File names are sanitised and unique.
.write_exports <- function(rv, formats, scope, dir) {
  st <- at_session_status(rv$session)
  idx <- .export_targets(rv, scope)
  overlap <- rv$overlap %||% "last"
  stems <- .unique_components(.safe_component(st$name))
  rows <- list(); skipped <- character(0); failed <- character(0)
  for (i in idx) {
    name <- st$name[i]
    stem <- stems[i]
    proj <- if (i == rv$cursor) rv$project else rv$session$projects[[i]]
    if (is.null(proj) || nrow(at_rois(proj)) == 0L) {
      skipped <- c(skipped, name); next
    }
    tryCatch({
      if ("mask_tiff" %in% formats) {
        p <- file.path(dir, paste0(stem, ".tif"))
        at_write_mask(at_mask(proj, "labelled", overlap = overlap), p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(image = name, format = "mask_tiff", path = p)
      }
      if ("geojson" %in% formats) {
        p <- file.path(dir, paste0(stem, ".geojson"))
        at_write_geojson(proj, p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(image = name, format = "geojson", path = p)
      }
      if ("qupath" %in% formats) {
        p <- file.path(dir, paste0(stem, "_qupath.geojson"))
        at_write_qupath(proj, p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(image = name, format = "qupath", path = p)
      }
      if ("csv" %in% formats) {
        p <- file.path(dir, paste0(stem, "_rois.csv"))
        at_write_rois_csv(proj, p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(image = name, format = "csv", path = p)
      }
    }, error = function(e) failed <<- c(failed, sprintf("%s (%s)", name, conditionMessage(e))))
  }
  rc <- if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(image = character(), format = character(), path = character())
  }
  attr(rc, "skipped") <- skipped
  attr(rc, "failed") <- failed
  rc
}

# Zip `paths` (relative to `root`, keeping sub-directories) into `zipfile`.
.zip_into <- function(zipfile, paths, root) {
  root_n <- normalizePath(root, winslash = "/")
  files <- vapply(paths, function(p) .relative_to(p, root_n), character(1), USE.NAMES = FALSE)
  if (requireNamespace("zip", quietly = TRUE)) {
    zip::zip(zipfile = zipfile, files = files, root = root_n)
  } else {
    old <- setwd(root_n); on.exit(setwd(old))
    utils::zip(zipfile = zipfile, files = files, flags = "-q")
  }
}

mod_export_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    receipt <- shiny::reactiveVal(NULL)
    handoff <- shiny::reactiveVal(NULL)
    output$receipt <- shiny::renderTable(receipt())

    output$run <- shiny::downloadHandler(
      filename = function() sprintf("annotatR_export_%s.zip", input$scope %||% "current"),
      content = function(file) {
        dir <- file.path(rv$session$out_dir, "export")
        if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
        rc <- if (is.null(rv$project)) NULL else
          .write_exports(rv, input$formats, input$scope %||% "current", dir)
        receipt(rc)
        paths <- if (is.null(rc)) character(0) else rc$path
        if (length(attr(rc, "failed"))) {
          shiny::showNotification(paste("Export failed for:", paste(attr(rc, "failed"), collapse = "; ")),
                                  type = "error")
        }
        legends <- paste0(paths[grepl("\\.tif$", paths)], ".legend.json")
        paths <- unique(c(paths, legends[file.exists(legends)]))
        if (!length(paths)) {
          note <- file.path(dir, "README.txt")
          writeLines(c("annotatR export",
                       sprintf("Scope '%s' matched no annotated images to export.",
                               input$scope %||% "current")), note)
          paths <- note
        }
        .zip_into(file, paths, dir)
      }
    )

    write_handoff <- function() {
      shiny::req(rv$project)
      nm <- .safe_component(trimws(input$handoff_name %||% ""))
      if (identical(nm, "item")) nm <- paste0("handoff-", format(Sys.time(), "%Y%m%d-%H%M%S"))
      dest <- file.path(rv$session$out_dir, "handoff", nm)
      proj <- rv$project
      rc <- tryCatch(at_export_qupflowr(proj, dest, formats = c("qupath_geojson", "geojson",
                                                                "mask_tiff", "manifest"),
                                        overwrite = file.exists(file.path(dest, "integrity.json"))),
                     error = function(e) e)
      handoff(rc)
      rc
    }
    shiny::observeEvent(input$handoff, write_handoff())
    output$handoff_status <- shiny::renderText({
      rc <- handoff()
      if (is.null(rc)) return("No handoff written yet.")
      if (inherits(rc, "error")) return(paste("Handoff failed:", conditionMessage(rc)))
      sprintf("%s\n%d files, digest %s", basename(rc$destination), nrow(rc$files), rc$handoff_digest)
    })
    output$handoff_zip <- shiny::downloadHandler(
      filename = function() "annotatR_qupflowr_handoff.zip",
      content = function(file) {
        rc <- write_handoff()
        if (inherits(rc, "error")) {
          .at_abort("The handoff could not be written: {conditionMessage(rc)}", class = "io",
                    code = "WRITE_FAILED")
        }
        .zip_into(file, file.path(rc$destination, c(rc$files$path, "integrity.json")), rc$destination)
      }
    )
    receipt
  })
}

# ---- Session: save, status badge ----------------------------------------------------

mod_session_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::actionButton(ns("save"), "\U0001f4be Save"),
    shiny::actionButton(ns("complete"), "\u2713 Complete"),
    shiny::actionButton(ns("flag"), "\u2691 Flag"),
    shiny::span(class = "at-saved", shiny::textOutput(ns("saved"), inline = TRUE)),
    shiny::uiOutput(ns("badge"), inline = TRUE)
  )
}

# Drop the bulky in-memory pixel handle before serialising: the image is
# re-opened from its source path on resume.
.lite_project <- function(p) {
  if (!is.null(p) && !is.null(p$image)) p$image$handle <- NULL
  p
}

# The annotation state shown to the user and reported to controllers.
.annotation_status <- function(rv) {
  if (isTRUE(rv$read_only)) return("read_only")
  if (!is.null(rv$staged)) return("staged")
  if (identical(rv$saved, "unsaved")) return("unsaved")
  if (!is.null(rv$last_commit) && identical(rv$last_action, "commit")) return("committed")
  "saved"
}

mod_session_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    save_now <- function() {
      if (isTRUE(rv$read_only)) return(invisible(FALSE))
      rv$saved <- "saving"
      pdir <- file.path(rv$session$out_dir, "projects")
      if (!dir.exists(pdir)) dir.create(pdir, recursive = TRUE)
      if (!is.null(rv$project)) {
        rv$session$projects[[rv$cursor]] <- rv$project
        name <- .safe_component(at_session_status(rv$session)$name[rv$cursor])
        rv$session$manifest$n_rois[rv$cursor] <- nrow(at_rois(rv$project))
        at_save_project(.lite_project(rv$project), file.path(pdir, paste0(name, ".rds")),
                        overwrite = TRUE)
      }
      sess <- rv$session
      sess$projects <- lapply(sess$projects, .lite_project)
      at_save_session(sess, overwrite = TRUE)
      rv$saved <- "saved"
      invisible(TRUE)
    }
    shiny::observeEvent(input$save, save_now())
    shiny::observeEvent(rv$trigger_save, save_now(), ignoreInit = TRUE)
    shiny::observeEvent(input$complete, {
      rv$session <- at_set_status(rv$session, rv$cursor, "complete")
      save_now()
    })
    shiny::observeEvent(input$flag, {
      rv$session <- at_set_status(rv$session, rv$cursor, "flagged")
    })
    shiny::observeEvent(rv$project, {
      if (isTRUE(rv$session$autosave) && identical(rv$saved, "unsaved")) {
        save_now()
      }
    }, ignoreInit = TRUE)
    output$saved <- shiny::renderText({
      switch(rv$saved %||% "saved",
             saved = "\u2713 saved", saving = "\u27f3 saving\u2026",
             unsaved = "\u26a0 unsaved")
    })
    output$badge <- shiny::renderUI({
      st <- .annotation_status(rv)
      label <- c(read_only = "read-only", staged = "staged", unsaved = "unsaved",
                 committed = "committed", saved = "saved")[[st]]
      shiny::span(class = paste0("at-badge at-badge-", st), `data-state` = st,
                  role = "status", label)
    })
    list(save_now = save_now)
  })
}

# ---- Help -------------------------------------------------------------------------------

.shortcut_table <- function() {
  data.frame(
    key = c("n / p", "N", "1-9", "q w e r t y", "d", "Ctrl+Z / Ctrl+Shift+Z",
            "Shift+Enter", "Shift+V", "f", "s", "Ctrl+E", "?"),
    action = c("next / previous image", "next pending image", "select label",
               "tool: pan/rect/polygon/freehand/circle/point", "delete last ROI",
               "undo / redo", "mark complete & advance",
               "paste previous image's ROIs", "flag image", "save session",
               "open export", "shortcut help"),
    stringsAsFactors = FALSE
  )
}

mod_help_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::actionButton(ns("show"), "? shortcuts", class = "btn-block")
}

mod_help_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    output$shortcuts <- shiny::renderTable(.shortcut_table())
    show_help <- function() {
      shiny::showModal(shiny::modalDialog(
        title = "Keyboard shortcuts",
        shiny::tableOutput(session$ns("shortcuts")),
        easyClose = TRUE, footer = shiny::modalButton("Close")
      ))
    }
    shiny::observeEvent(input$show, show_help())
    shiny::observeEvent(rv$trigger_help, show_help(), ignoreInit = TRUE)
  })
}

# ---- Dashboard ------------------------------------------------------------------------------

.metric_tile <- function(value, label) {
  shiny::div(class = "at-tile",
             shiny::div(class = "at-tile-val", value),
             shiny::div(class = "at-tile-lab", label))
}

mod_dashboard_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Progress"),
    shiny::uiOutput(ns("tiles")),
    shiny::br(),
    bslib::layout_columns(
      col_widths = c(7, 5),
      bslib::card(bslib::card_header("ROIs per image"),
                  shiny::plotOutput(ns("plot"), height = "300px")),
      bslib::card(bslib::card_header("Queue status"),
                  shiny::tableOutput(ns("status")))
    )
  )
}

mod_dashboard_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    status <- shiny::reactive({
      shiny::req(rv$session)
      rv$cursor
      rv$saved
      at_session_status(rv$session)
    })
    output$tiles <- shiny::renderUI({
      m <- status()
      shiny::div(
        class = "at-tiles",
        .metric_tile(nrow(m), "images"),
        .metric_tile(sum(m$status == "complete"), "complete"),
        .metric_tile(sum(m$status == "pending"), "pending"),
        .metric_tile(sum(m$status == "flagged"), "flagged"),
        .metric_tile(sum(m$n_rois), "ROIs total")
      )
    })
    output$status <- shiny::renderTable({
      m <- status()
      agg <- as.data.frame(table(factor(m$status,
        levels = c("pending", "in_progress", "complete", "flagged", "skipped"))))
      names(agg) <- c("status", "images")
      agg[agg$images > 0, , drop = FALSE]
    })
    output$plot <- shiny::renderPlot({
      m <- status()
      df <- data.frame(image = factor(m$name, levels = m$name),
                       n = m$n_rois, status = m$status)
      ggplot2::ggplot(df, ggplot2::aes(x = .data$image, y = .data$n, fill = .data$status)) +
        ggplot2::geom_col() +
        ggplot2::scale_fill_manual(values = c(
          pending = "#7f93a8", in_progress = "#e3a008", complete = "#1f6feb",
          flagged = "#d55e00", skipped = "#495867"), drop = FALSE) +
        ggplot2::labs(x = NULL, y = "ROIs", fill = NULL) +
        ggplot2::coord_flip() +
        ggplot2::theme_minimal(base_size = 12)
    })
  })
}

# ---- Data -----------------------------------------------------------------------------------

.data_exts <- "\\.(dat|hdr|tif|tiff|png|jpe?g|qptiff|cu3|cu3s)$"

mod_data_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Data source"),
    bslib::layout_columns(
      col_widths = c(9, 3),
      shiny::textInput(ns("dir"), NULL, placeholder = "/path/to/a/folder of images or cubes"),
      shiny::actionButton(ns("load"), "Load folder", class = "btn-primary")
    ),
    shiny::div(class = "at-progress", shiny::textOutput(ns("msg"), inline = TRUE)),
    shiny::h5("Import reviewed annotations (qupflowR handoff)"),
    bslib::layout_columns(
      col_widths = c(9, 3),
      shiny::textInput(ns("handoff"), NULL, placeholder = "/path/to/handoff directory or QuPath GeoJSON"),
      shiny::actionButton(ns("stage"), "Stage import")
    ),
    shiny::div(class = "at-progress", shiny::textOutput(ns("stage_msg"), inline = TRUE)),
    shiny::h5("Current queue"),
    shiny::tableOutput(ns("table"))
  )
}

mod_data_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    msg <- shiny::reactiveVal("")
    stage_msg <- shiny::reactiveVal("")
    shiny::observeEvent(input$load, {
      d <- input$dir
      if (!nzchar(d) || !dir.exists(d)) {
        msg("Folder not found."); return()
      }
      files <- list.files(d, pattern = .data_exts, recursive = TRUE,
                          full.names = TRUE, ignore.case = TRUE)
      cubes <- files[grepl("_SpecCube\\.dat$", files, ignore.case = TRUE)]
      if (length(cubes)) files <- cubes
      if (!length(files)) {
        msg("No supported images found in that folder."); return()
      }
      new_sess <- tryCatch(
        at_session(files, labels = rv$session$labels, layers = rv$session$layer_spec,
                   out_dir = rv$session$out_dir),
        error = function(e) e)
      if (inherits(new_sess, "error")) {
        msg(paste("Load failed:", conditionMessage(new_sess))); return()
      }
      rv$session <- new_sess
      rv$cursor <- 1L
      rv$generation <- (rv$generation %||% 0L) + 1L
      msg(sprintf("Loaded %d image(s).", nrow(new_sess$manifest)))
    })
    output$msg <- shiny::renderText(msg())

    shiny::observeEvent(input$stage, {
      shiny::req(rv$project)
      path <- trimws(input$handoff %||% "")
      if (!nzchar(path) || !file.exists(path)) {
        stage_msg("Handoff not found."); return()
      }
      res <- tryCatch({
        rep <- at_import_qupflowr(path)
        at_stage_qupflowr(rv$project, rep)
      }, error = function(e) e)
      if (inherits(res, "error")) {
        stage_msg(paste("Import refused:", conditionMessage(res))); return()
      }
      rv$staged <- res
      s <- res$summary
      stage_msg(sprintf("Staged: %d create, %d update, %d conflict. Review it on the Annotate page.",
                        s$create, s$update, s$conflict))
    })
    output$stage_msg <- shiny::renderText(stage_msg())

    output$table <- shiny::renderTable({
      shiny::req(rv$session)
      rv$cursor
      m <- at_session_status(rv$session)
      data.frame(idx = m$idx, name = m$name, status = m$status, n_rois = m$n_rois)
    })
  })
}
