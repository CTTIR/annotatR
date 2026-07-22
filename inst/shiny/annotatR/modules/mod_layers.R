# Layers module: active layer/label selection, plus adding custom layers and
# custom labels to the current image's project.

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
        return(shiny::div(class = "at-progress", "No labels yet — add one below."))
      }
      shiny::radioButtons(session$ns("label"), NULL, choices = labs,
                          selected = rv$active_label)
    })
    shiny::observeEvent(input$layer, {
      rv$active_layer <- input$layer
      # Follow the layer's first label when switching layers.
      labs <- rv$project$layers[[input$layer]]$labels
      rv$active_label <- if (length(labs)) labs[1] else NULL
    })
    shiny::observeEvent(input$label, {
      rv$active_label <- input$label
    })

    # Add a custom layer (with a starter label = its name, so it is immediately
    # usable) and make it active.
    shiny::observeEvent(input$add_layer, {
      shiny::req(rv$project)
      nm <- trimws(input$new_layer %||% "")
      if (nzchar(nm) && !(nm %in% names(rv$project$layers))) {
        rv$project <- annotatR::at_add_layer(rv$project,
                                             annotatR::at_layer(nm, labels = nm))
        rv$active_layer <- nm
        rv$active_label <- nm
        shiny::updateTextInput(session, "new_layer", value = "")
      }
    })

    # Add a custom label to the active layer's vocabulary, give it a colour, and
    # select it.
    shiny::observeEvent(input$add_label, {
      shiny::req(rv$project, rv$active_layer)
      new_lab <- trimws(input$new_label %||% "")
      if (!nzchar(new_lab)) return()
      lyr <- rv$project$layers[[rv$active_layer]]
      if (!(new_lab %in% lyr$labels)) {
        lyr$labels <- c(lyr$labels, new_lab)
        cols <- lyr$style$colour
        if (is.null(cols)) cols <- character(0)
        if (!(new_lab %in% names(cols))) {
          cols[new_lab] <- .at_label_palette[(length(cols) %% length(.at_label_palette)) + 1L]
        }
        lyr$style$colour <- cols
        rv$project$layers[[rv$active_layer]] <- lyr
        rv$active_label <- new_lab
        rv$saved <- "unsaved"
        shiny::updateTextInput(session, "new_label", value = "")
      }
    })
  })
}
