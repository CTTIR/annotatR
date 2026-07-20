# Spectrum module: spectral plot for cube images; hidden for non-spectral.

mod_spectrum_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::uiOutput(ns("panel"))
}

mod_spectrum_server <- function(id, rv) {
  shiny::moduleServer(id, function(input, output, session) {
    is_spectral <- shiny::reactive({
      shiny::req(rv$project)
      annotatR::at_is_spectral(rv$project$image)
    })
    output$panel <- shiny::renderUI({
      if (!is_spectral()) {
        return(NULL)
      }
      shiny::tagList(shiny::h5("Spectra"),
                     shiny::plotOutput(session$ns("plot"), height = "200px"))
    })
    output$plot <- shiny::renderPlot({
      shiny::req(rv$project, is_spectral())
      # at_extract_spectrum returns a 0-row tibble when there are no ROIs, which
      # at_plot_spectrum renders as an empty plot.
      annotatR::at_plot_spectrum(annotatR::at_extract_spectrum(rv$project))
    })
    is_spectral
  })
}
