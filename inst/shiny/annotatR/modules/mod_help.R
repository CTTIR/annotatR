# Help module: keyboard shortcut reference and workflow guidance.

.shortcut_table <- function() {
  data.frame(
    key = c("n / p", "N", "1-9", "q w e r t y", "d", "Ctrl+Z / Ctrl+Shift+Z",
            "Space", "Enter", "Shift+Enter", "Shift+V", "f", "s", "Ctrl+E", "?"),
    action = c("next / previous image", "next pending image", "select label",
               "tool: pan/rect/polygon/freehand/circle/point", "delete selected ROI",
               "undo / redo", "toggle mask overlay", "commit ROI and stay",
               "commit, mark complete, advance", "paste previous image's ROIs",
               "flag image", "save session", "open export", "shortcut help"),
    stringsAsFactors = FALSE
  )
}

mod_help_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::actionButton(ns("show"), "?"),
    shiny::conditionalPanel(
      condition = sprintf("input['%s'] %% 2 == 1", ns("show")),
      shiny::tableOutput(ns("shortcuts"))
    )
  )
}

mod_help_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    output$shortcuts <- shiny::renderTable(.shortcut_table())
  })
}
