# Compatibility entry point for shiny::runApp() on this directory. All app code
# lives in the annotatR package; the app object comes from annotatR::at_app().
# An annot_session may be passed through the legacy option `annotatR.session`,
# which is read here only for this compatibility path.
annotatR::at_app(session = getOption("annotatR.session", default = NULL))
