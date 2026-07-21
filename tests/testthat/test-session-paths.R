# A session reads its images lazily, and at_annotate() launches the app with
# shiny::runApp(), which changes the working directory. So a session built with
# relative paths must still resolve its images afterwards -- at_session() has to
# store absolute paths.

test_that("at_session resolves image paths absolutely (survives a working-dir change)", {
  dir <- withr::local_tempdir()
  writeLines("x", file.path(dir, "a.png"))
  writeLines("x", file.path(dir, "b.png"))
  s <- withr::with_dir(dir, at_session(c("a.png", "b.png"), out_dir = dir))
  # The stored paths must resolve from ANY working directory, not just `dir`.
  other <- withr::local_tempdir()
  resolved <- withr::with_dir(other, file.exists(s$manifest$path))
  expect_true(all(resolved))
})
