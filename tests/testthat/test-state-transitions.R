skip_if_not_installed("shiny")
source(system.file("shiny", "annotatR", "modules", "mod_state.R", package = "annotatR"),
       local = TRUE)

transition_state <- function() {
  s <- demo_session(2)
  s$autosave <- FALSE
  p <- at_project(tiny_image(), at_layer("base", labels = "a"),
                  entry_id = s$manifest$entry_id[1])
  rv <- shiny::reactiveValues(session = s, cursor = 1L, project = p, saved = "saved")
  .state_init(rv)
  rv
}

test_that("undoing layers and labels leaves a valid drawing selection", {
  shiny::isolate({
    rv <- transition_state()
    .state_mutate(rv, function(p) at_add_layer(p, at_layer("custom", labels = "b")))
    rv$active_layer <- "custom"; rv$active_label <- "b"
    .state_undo(rv)
    expect_identical(rv$active_layer, "base")
    expect_identical(rv$active_label, "a")
    .state_mutate(rv, function(p) {
      p$layers$base$labels <- c("a", "new")
      p
    })
    rv$active_label <- "new"
    .state_undo(rv)
    expect_identical(rv$active_label, "a")
    .state_mutate(rv, function(p) at_add_roi(p, rv$active_layer,
                                            at_roi_point(2, 2, rv$active_label)))
    expect_equal(nrow(at_rois(rv$project)), 1L)
  })
})
