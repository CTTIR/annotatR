# Layers module: active layer/label selection and layer management.

mod_layers_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tagList(
    shiny::h5("Layers"),
    shiny::uiOutput(ns("layer_sel")),
    shiny::actionButton(ns("add_layer"), "+ layer"),
    shiny::textInput(ns("new_layer"), NULL, placeholder = "new layer name"),
    shiny::h5("Labels"),
    shiny::uiOutput(ns("label_sel"))
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
      shiny::radioButtons(session$ns("label"), NULL, choices = labs,
                          selected = rv$active_label)
    })
    shiny::observeEvent(input$layer, {
      rv$active_layer <- input$layer
    })
    shiny::observeEvent(input$label, {
      rv$active_label <- input$label
    })
    shiny::observeEvent(input$add_layer, {
      shiny::req(rv$project, nzchar(input$new_layer))
      if (!(input$new_layer %in% names(rv$project$layers))) {
        rv$project <- annotatR::at_add_layer(rv$project, annotatR::at_layer(input$new_layer))
        rv$active_layer <- input$new_layer
      }
    })
  })
}
