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
      shiny::textInput(ns("new_layer"), "New layer name", placeholder = "new layer name"),
      .at_action(ns("add_layer"), "+ layer", fields = list(new_layer = ns("new_layer")))
    ),
    shiny::h5("Labels"),
    shiny::uiOutput(ns("label_sel")),
    shiny::div(
      class = "at-add-row",
      shiny::textInput(ns("new_label"), "New label name", placeholder = "new label name"),
      .at_action(ns("add_label"), "+ label", fields = list(new_label = ns("new_label"), layer = ns("layer")))
    )
  )
}

mod_layers_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    .state_init(rv)
    output$layer_sel <- shiny::renderUI({
      shiny::req(rv$project)
      shiny::radioButtons(session$ns("layer"), "Layer",
                          choices = stats::setNames(names(rv$project$layers), vapply(rv$project$layers, function(layer) paste0(layer$name,
                            if (isTRUE(layer$style$locked)) " (locked)" else "",
                            if (identical(layer$style$visible, FALSE)) " (hidden)" else ""), character(1))),
                          selected = shiny::isolate(rv$active_layer))
    })
    output$label_sel <- shiny::renderUI({
      shiny::req(rv$project, rv$active_layer)
      lyr <- rv$project$layers[[rv$active_layer]]
      labs <- lyr$labels
      if (length(labs) == 0L) {
        return(shiny::div(class = "at-progress", "No labels yet — add one below."))
      }
      shiny::radioButtons(session$ns("label"), "Label", choices = labs,
                          selected = shiny::isolate(rv$active_label))
    })
    shiny::observeEvent(rv$active_layer, {
      shiny::updateRadioButtons(session, "layer", selected = rv$active_layer)
    })
    shiny::observeEvent(rv$active_label, {
      shiny::updateRadioButtons(session, "label", selected = rv$active_label)
    })
    shiny::observeEvent(input$layer_intent, {
      event <- .state_event(rv, input$layer_intent, fields = c("value"))
      shiny::req(event, event$payload$value %in% names(rv$project$layers))
      if (identical(rv$active_layer, event$payload$value)) return()
      rv$active_layer <- event$payload$value
      # Follow the layer's first label when switching layers.
      labs <- rv$project$layers[[event$payload$value]]$labels
      rv$active_label <- if (length(labs)) labs[1] else NULL
    })
    shiny::observeEvent(input$label_intent, {
      event <- .state_event(rv, input$label_intent, fields = c("value", "layer"))
      shiny::req(event, identical(event$payload$layer, rv$active_layer),
                 event$payload$value %in% rv$project$layers[[rv$active_layer]]$labels)
      rv$active_label <- event$payload$value
    })

    # Add a custom layer (with a starter label = its name, so it is immediately
    # usable) and make it active.
    shiny::observeEvent(input$add_layer, {
      event <- .state_event(rv, input$add_layer, fields = c("new_layer"))
      shiny::req(event, rv$project, !identical(rv$display_ready, FALSE))
      nm <- trimws(event$payload$new_layer %||% "")
      if (nzchar(nm) && !(nm %in% names(rv$project$layers))) {
        .state_mutate(rv, function(p) annotatR::at_add_layer(p,
                       annotatR::at_layer(nm, labels = nm)),
                       event)
        rv$active_layer <- nm
        rv$active_label <- nm
        shiny::updateTextInput(session, "new_layer", value = "")
      }
    })

    # Add a custom label to the active layer's vocabulary, give it a colour, and
    # select it.
    shiny::observeEvent(input$add_label, {
      event <- .state_event(rv, input$add_label, fields = c("new_label", "layer"))
      shiny::req(event, rv$project, rv$active_layer, !identical(rv$display_ready, FALSE))
      layer <- event$payload$layer
      shiny::req(is.character(layer), length(layer) == 1L, layer %in% names(rv$project$layers),
                 !isTRUE(rv$project$layers[[layer]]$style$locked))
      new_lab <- trimws(event$payload$new_label %||% "")
      if (!nzchar(new_lab)) return()
      lyr <- rv$project$layers[[layer]]
      if (!(new_lab %in% lyr$labels)) {
        lyr$labels <- c(lyr$labels, new_lab)
        cols <- lyr$style$colour
        if (is.null(cols)) cols <- character(0)
        if (!(new_lab %in% names(cols))) {
          cols[new_lab] <- .at_label_palette[(length(cols) %% length(.at_label_palette)) + 1L]
        }
        lyr$style$colour <- cols
        .state_mutate(rv, function(p) {
          p$layers[[layer]] <- lyr
          p
        }, event)
        if (identical(layer, rv$active_layer)) rv$active_label <- new_lab
        shiny::updateTextInput(session, "new_label", value = "")
      }
    })
  })
}
