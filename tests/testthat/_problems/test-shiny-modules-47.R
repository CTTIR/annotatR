# Extracted from test-shiny-modules.R:47

# prequel ----------------------------------------------------------------------
skip_if_not_installed("shiny")
.mod_dir <- system.file("shiny", "annotatR", "modules", package = "annotatR")
for (.f in list.files(.mod_dir, pattern = "\\.R$", full.names = TRUE)) {
  source(.f, local = TRUE)
}
make_rv <- function(project = demo_project(), session = demo_session(3)) {
  shiny::reactiveValues(
    session = session, cursor = 1L, project = project, tool = "pan",
    active_layer = "tissue", active_label = "tissue", mask_type = "labelled",
    overlap = "last", undo = list(), redo = list(), saved = "saved"
  )
}

# test -------------------------------------------------------------------------
rv <- make_rv()
before <- nrow(at_rois(rv$project))
