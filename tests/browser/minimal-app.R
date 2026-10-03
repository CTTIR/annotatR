# Run against an installed package in a library where magick is absent.
# This is a real dependency-absence qualification, with no behavior mocks.
library(annotatR)
stopifnot(!requireNamespace("magick",quietly=TRUE),requireNamespace("tiff",quietly=TRUE))
fixture <- tempfile("annotatr-minimal-");dir.create(fixture)
tif <- file.path(fixture,"readable.tif")
tiff::writeTIFF(matrix(seq_len(100)/100,10,10),tif)
img <- at_read_image(tif)
source <- at_tile_source(img)
stopifnot(is.null(source$dataUri),grepl("magick",source$displayError))
png_error <- tryCatch(at_example_image("tissue"),error=function(e) conditionMessage(e))
stopifnot(is.character(png_error),grepl("PNG.*magick",png_error))
cat(jsonlite::toJSON(list(libraries=.libPaths(),magick=FALSE,tiff=TRUE,
  tiff_dims=at_dims(img),display_error=source$displayError,png_error=png_error),auto_unbox=TRUE),"\n")
options(annotatR.session=at_session(tif,labels="a",out_dir=file.path(fixture,"saved"),autosave=FALSE))
shiny::runApp(system.file("shiny","annotatR",package="annotatR"),host="127.0.0.1",
  port=as.integer(Sys.getenv("ANNOTATR_BROWSER_PORT","5820")),launch.browser=FALSE)
