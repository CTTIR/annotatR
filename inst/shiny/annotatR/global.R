# annotatR batch-annotation app — shared setup.
#
# Every call in this app is namespace-qualified; no package attaching anywhere.
#
# Cross-module state lives in a single reactiveValues object `rv`, created in the
# server (see app.R) and passed to every module server. Its fields:
#
#   rv$session      annot_session          the queue, manifest, and settings
#   rv$cursor       integer(1)             current image index (mirrors session)
#   rv$project      annot_project | NULL   the current image's project
#   rv$tool         character(1)           active drawing tool
#   rv$active_layer character(1)           layer new ROIs land in
#   rv$active_label character(1)           label applied to new ROIs
#   rv$mask_type    character(1)           "binary" | "labelled" | "multiclass"
#   rv$overlap      character(1)           overlap policy for the mask
#   rv$undo         list                   per-project undo stack of projects
#   rv$redo         list                   per-project redo stack of projects
#   rv$saved        character(1)           "saved" | "saving" | "unsaved"
#   rv$saved_at     POSIXct                last autosave time
#
# The session is passed in from at_annotate() via getOption("annotatR.session").

# Read the session the launcher stashed for this app instance.
.app_session <- function() {
  s <- getOption("annotatR.session", default = NULL)
  if (is.null(s)) {
    s <- annotatR::at_example_session(3)
  }
  s
}

# Suite accent colour (Hugo Coder blue; the gold is used for ROI handles).
.app_accent <- "#1f6feb"

# The app theme: Hugo Coder colour language. Bootstrap 5 with a blue primary and
# JetBrains Mono display type; the navy dark palette is finished in custom.css,
# keyed on data-bs-theme so the light/dark/auto toggle switches it. Fonts are
# system/local only (no CDN) so the app works fully offline.
.app_theme <- function() {
  bslib::bs_theme(
    version = 5,
    primary = .app_accent,
    base_font = bslib::font_collection(
      "Inter", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"),
    code_font = bslib::font_collection(
      "JetBrains Mono", "ui-monospace", "SFMono-Regular", "Menlo", "monospace"),
    heading_font = bslib::font_collection(
      "JetBrains Mono", "Inter", "system-ui")
  )
}
