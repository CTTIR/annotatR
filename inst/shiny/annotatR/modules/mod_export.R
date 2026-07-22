# Export module: choose formats + scope, then download the results as a zip.
# Files are also written to <out_dir>/export as a persistent copy.

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
    shiny::helpText("Downloads a .zip; a copy is also written to the session's",
                    "export folder."),
    shiny::tableOutput(ns("receipt"))
  )
}

# Images to export for a given scope. The current image always uses the live
# (possibly unsaved) project; others use the last saved project in the session.
.export_targets <- function(rv, scope) {
  st <- annotatR::at_session_status(rv$session)
  switch(scope,
         current  = rv$cursor,
         complete = which(st$status == "complete"),
         flagged  = which(st$status == "flagged"),
         all      = seq_len(nrow(st)))
}

# Write the selected formats for every in-scope annotated image into `dir`.
# Returns a receipt data.frame (image, format, path); skipped/failed image
# names are carried as attributes.
.write_exports <- function(rv, formats, scope, dir) {
  st <- annotatR::at_session_status(rv$session)
  idx <- .export_targets(rv, scope)
  overlap <- rv$overlap %||% "last"
  rows <- list(); skipped <- character(0); failed <- character(0)
  for (i in idx) {
    name <- st$name[i]
    proj <- if (i == rv$cursor) rv$project else rv$session$projects[[i]]
    if (is.null(proj) || nrow(annotatR::at_rois(proj)) == 0L) {
      skipped <- c(skipped, name); next
    }
    tryCatch({
      if ("mask_tiff" %in% formats) {
        p <- file.path(dir, paste0(name, ".tif"))
        annotatR::at_write_mask(annotatR::at_mask(proj, "labelled", overlap = overlap),
                                p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(image = name, format = "mask_tiff", path = p)
      }
      if ("geojson" %in% formats) {
        p <- file.path(dir, paste0(name, ".geojson"))
        annotatR::at_write_geojson(proj, p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(image = name, format = "geojson", path = p)
      }
      if ("qupath" %in% formats) {
        p <- file.path(dir, paste0(name, "_qupath.geojson"))
        annotatR::at_write_qupath(proj, p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(image = name, format = "qupath", path = p)
      }
      if ("csv" %in% formats) {
        p <- file.path(dir, paste0(name, "_rois.csv"))
        annotatR::at_write_rois_csv(proj, p, overwrite = TRUE)
        rows[[length(rows) + 1L]] <- data.frame(image = name, format = "csv", path = p)
      }
    }, error = function(e) failed <<- c(failed, sprintf("%s (%s)", name, conditionMessage(e))))
  }
  rc <- if (length(rows)) do.call(rbind, rows) else NULL
  attr(rc, "skipped") <- skipped
  attr(rc, "failed") <- failed
  rc
}

# Zip `paths` (flat, by basename) from `root` into `zipfile`.
.zip_into <- function(zipfile, paths, root) {
  files <- basename(paths)
  if (requireNamespace("zip", quietly = TRUE)) {
    zip::zip(zipfile = zipfile, files = files, root = root)
  } else {
    old <- setwd(root); on.exit(setwd(old))
    utils::zip(zipfile = zipfile, files = files, flags = "-jq")
  }
}

mod_export_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    receipt <- shiny::reactiveVal(NULL)
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
        # bundle the mask legend written next to each tiff
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
    receipt
  })
}
