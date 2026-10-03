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
    shiny::textOutput(ns("outcome")),
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
# Returns every image-format outcome, including paired sidecars and failures.
.write_exports <- function(rv, formats, scope, dir) {
  rc <- annotatR:::.export_session_items(rv$session,.export_targets(rv,scope),dir,formats,
    function(i) if(i==rv$cursor) rv$project else rv$session$projects[[i]],
    overwrite=TRUE,overlap=rv$overlap %||% "last",flat=TRUE,skip_empty=TRUE)
  rc <- annotatR:::.export_receipt_files(rc,dir)
  attr(rc,"skipped") <- unique(rc$entry_id[rc$status=="skipped"])
  attr(rc,"failed") <- rc$message[rc$status=="error"]
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
    output$outcome <- shiny::renderText({
      rc <- receipt()
      if(is.null(rc)) return("")
      paste0(sum(rc$status=="ok"), " complete; ", sum(rc$status=="error"),
             " failed; ", sum(rc$status=="skipped"), " skipped.",
             if(!is.null(attr(rc,"receipt_error"))) paste0(" Receipt file failed: ",attr(rc,"receipt_error")))
    })

    output$run <- shiny::downloadHandler(
      filename = function() sprintf("annotatR_export_%s.zip", input$scope %||% "current"),
      content = function(file) {
        dir <- file.path(rv$session$out_dir, "export")
        if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
        rc <- .write_exports(rv, input$formats, input$scope %||% "current", dir)
        receipt(rc)

        paths <- if(is.null(rc)) character() else c(rc$path[rc$status=="ok"],rc$sidecar_path[rc$status=="ok"])
        paths <- unique(paths[!is.na(paths)])
        manifest <- file.path(dir,"_export_manifest.csv")
        if(!is.null(rc) && is.null(attr(rc,"receipt_error")) && file.exists(manifest)) paths <- c(paths,manifest)
        if(!length(paths)) stop("Export produced no complete files or receipt.")
        .zip_into(file, paths, dir)
      }
    )
    receipt
  })
}
