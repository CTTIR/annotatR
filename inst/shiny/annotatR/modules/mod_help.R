# Help module: a keyboard-shortcut reference shown in a modal, openable from the
# "?" button or the "?" key. Only shortcuts with a live action are listed.

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
