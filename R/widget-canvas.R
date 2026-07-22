# The atcanvas htmlwidget: a deep-zoom viewer with ROI drawing.
#
# For v0.0.1 the JavaScript is a self-contained HTML5 canvas (pan/zoom plus
# rectangle/polygon/point/freehand drawing) with no external libraries, so the
# widget works fully offline. The R interface is designed to be identical to
# what an OpenSeadragon + Annotorious implementation needs, so that engine can
# be swapped in later as a JS-only change (see STATE.md).
#
# COORDINATE DISCIPLINE: all coordinates that cross the JS -> R boundary are
# level-0 image pixels. The JS converts from canvas/screen coordinates to
# level-0 image pixels before emitting any event; the conversion is the single
# function `toImageCoords()` in atcanvas.js.

.canvas_deps_ok <- function(call = rlang::caller_env()) {
  missing <- character()
  for (p in c("htmlwidgets", "htmltools")) {
    if (!requireNamespace(p, quietly = TRUE)) missing <- c(missing, p)
  }
  if (length(missing) > 0L) {
    cli::cli_abort(
      c("The annotation canvas requires packages not installed.",
        "x" = "Missing: {.pkg {missing}}.",
        "i" = "Install with {.code install.packages(c({paste0('\"', missing, '\"', collapse = ', ')}))}."),
      call = call
    )
  }
  invisible(TRUE)
}

# Natural-colour RGB band triple: nearest bands to ~640/550/460 nm when the
# image has a visible-range spectral axis, else the first three bands. Turns a
# hyperspectral cube into a recognisable photo to annotate on -- pixel-aligned
# to the cube grid, so ROIs and spectra map exactly.
.default_rgb_bands <- function(img, nb) {
  if (nb < 3L) return(rep(1L, 3L))
  wl <- img$wavelengths
  if (!is.null(wl) && length(wl) == nb && min(wl, na.rm = TRUE) <= 700) {
    nearest <- function(target) which.min(abs(wl - target))
    return(c(nearest(640), nearest(550), nearest(460)))
  }
  1:3
}

# Downsampled base image as a PNG data URI, or NULL if it cannot be encoded.
.image_data_uri <- function(img, max_dim = 2048L) {
  if (!requireNamespace("magick", quietly = TRUE)) {
    return(NULL)
  }
  tryCatch({
    level <- .display_level(img, max_dim)
    tile <- at_tile(img, level = level)
    nb <- dim(tile)[3]
    bands <- .default_rgb_bands(img, nb)
    # Per-channel 2-98% contrast stretch. A flat min-max leaves cube channels
    # dark and washed out; the percentile stretch yields a natural-looking photo.
    stretch <- function(m) {
      q <- stats::quantile(m, c(0.02, 0.98), na.rm = TRUE)
      if (diff(q) == 0) return(matrix(0, nrow(m), ncol(m)))
      pmin(pmax((m - q[1]) / diff(q), 0), 1)
    }
    arr <- array(0, dim = c(dim(tile)[1], dim(tile)[2], 3L))
    for (k in 1:3) arr[, , k] <- stretch(tile[, , bands[k]])
    im <- magick::image_read(arr)
    raw <- magick::image_write(im, format = "png")
    paste0("data:image/png;base64,", jsonlite::base64_enc(raw))
  }, error = function(e) NULL)
}

#' Build a tile-source descriptor for the canvas
#'
#' @param img An [annot_image].
#' @param level_max Optional maximum level to expose; the image maximum by
#'   default.
#' @param tile_size Tile size in pixels. Default `512`.
#' @param embed Logical; embed a downsampled base image as a data URI (for the
#'   self-contained canvas). Default `TRUE`.
#' @param call The calling environment, for error reporting.
#' @return A list describing the image for the widget: `width`, `height`,
#'   `tileSize`, `minLevel`, `maxLevel`, `nBands`, and (when `embed`) `dataUri`.
#' @family shiny
#' @export
at_tile_source <- function(img, level_max = NULL, tile_size = 512L, embed = TRUE,
                           call = rlang::caller_env()) {
  .check_image(img, call = call)
  tile_size <- .check_count(tile_size, min = 1L, call = call)
  d0 <- at_dims(img, 0)
  maxl <- if (is.null(level_max)) img$n_levels - 1L else .check_count(level_max, call = call)
  src <- list(
    width = d0[1], height = d0[2], tileSize = tile_size,
    minLevel = 0L, maxLevel = maxl, nBands = img$n_bands
  )
  if (embed) {
    src$dataUri <- .image_data_uri(img)
  }
  src
}

#' An annotation canvas widget
#'
#' @param img An [annot_image] to display.
#' @param project Optional [annot_project] whose ROIs are shown initially.
#' @param tool Initial tool: one of `"pan"`, `"rect"`, `"polygon"`, `"freehand"`,
#'   `"circle"`, `"point"`, `"edit"`, `"erase"`.
#' @param width,height Widget dimensions.
#' @param elementId Optional element id.
#' @param options A list of extra options passed to the widget.
#' @param call The calling environment, for error reporting.
#'
#' @return An `htmlwidget` object.
#' @family shiny
#' @seealso [at_canvas_proxy()], [at_tile_source()]
#' @export
#' @examplesIf requireNamespace("htmlwidgets", quietly = TRUE) && (requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE))
#' at_canvas(at_example_image("tissue"))
at_canvas <- function(img, project = NULL, tool = "pan", width = NULL,
                      height = NULL, elementId = NULL, options = list(),
                      call = rlang::caller_env()) {
  .check_image(img, call = call)
  .canvas_deps_ok(call = call)
  tool <- .check_choice(tool, c("pan", "rect", "polygon", "freehand", "circle",
                                "point", "edit", "erase"), call = call)
  annotations <- if (!is.null(project)) {
    .check_project(project, call = call)
    .project_to_features(project, NULL, 0L, FALSE, at_dims(img, 0)[2], qupath = FALSE)
  } else {
    list(type = "FeatureCollection", features = list())
  }
  x <- list(
    tileSource = at_tile_source(img, call = call),
    annotations = annotations,
    tool = tool,
    options = options
  )
  htmlwidgets::createWidget(
    name = "atcanvas", x = x, width = width, height = height,
    package = "annotatR", elementId = elementId,
    sizingPolicy = htmlwidgets::sizingPolicy(defaultWidth = "100%", defaultHeight = 600,
                                             browser.fill = TRUE)
  )
}

#' Shiny output for the annotation canvas
#' @param outputId Output id.
#' @param width,height Output dimensions.
#' @return A Shiny output element.
#' @family shiny
#' @export
atCanvasOutput <- function(outputId, width = "100%", height = "600px") {
  htmlwidgets::shinyWidgetOutput(outputId, "atcanvas", width, height, package = "annotatR")
}

#' Render an annotation canvas in Shiny
#' @param expr An expression producing an [at_canvas()].
#' @param env The environment to evaluate `expr` in.
#' @param quoted Is `expr` already quoted?
#' @return A Shiny render function.
#' @family shiny
#' @export
renderAtCanvas <- function(expr, env = parent.frame(), quoted = FALSE) {
  if (!quoted) {
    expr <- substitute(expr)
  }
  htmlwidgets::shinyRenderWidget(expr, atCanvasOutput, env, quoted = TRUE)
}

# ---- Proxy (partial updates without re-rendering) --------------------------

#' A proxy for an existing annotation canvas
#'
#' Mirrors the `leafletProxy()` pattern: update a live canvas without
#' re-rendering the whole widget.
#'
#' @param id The canvas output id.
#' @param session The Shiny session.
#' @return An `atcanvas_proxy` object.
#' @family shiny
#' @export
at_canvas_proxy <- function(id, session = shiny::getDefaultReactiveDomain()) {
  structure(list(id = id, session = session), class = "atcanvas_proxy")
}

.canvas_msg <- function(proxy, method, payload, call = rlang::caller_env()) {
  .check_class(proxy, "atcanvas_proxy", call = call)
  msg <- c(list(id = proxy$id), payload)
  proxy$session$sendCustomMessage(paste0("atcanvas-", method), msg)
  invisible(proxy)
}

#' Replace the annotations on a canvas
#' @param proxy An `atcanvas_proxy`.
#' @param project An [annot_project].
#' @param layer Optional layer filter.
#' @param call The calling environment, for error reporting.
#' @return The proxy, invisibly.
#' @family shiny
#' @export
at_canvas_set_annotations <- function(proxy, project, layer = NULL,
                                      call = rlang::caller_env()) {
  .check_project(project, call = call)
  h <- at_dims(project$image, 0)[2]
  fc <- .project_to_features(project, layer, 0L, FALSE, h, qupath = FALSE)
  .canvas_msg(proxy, "set_annotations", list(annotations = fc), call = call)
}

#' Set the active drawing tool
#' @inheritParams at_canvas_set_annotations
#' @param tool One of the canvas tools.
#' @family shiny
#' @return The proxy, invisibly.
#' @export
at_canvas_set_tool <- function(proxy, tool, call = rlang::caller_env()) {
  tool <- .check_choice(tool, c("pan", "rect", "polygon", "freehand", "circle",
                                "point", "edit", "erase"), call = call)
  .canvas_msg(proxy, "set_tool", list(tool = tool), call = call)
}

#' Set the displayed band or RGB triple
#' @inheritParams at_canvas_set_annotations
#' @param band A band index or a length-3 vector of band indices.
#' @family shiny
#' @return The proxy, invisibly.
#' @export
at_canvas_set_band <- function(proxy, band, call = rlang::caller_env()) {
  .canvas_msg(proxy, "set_band", list(band = as.integer(band)), call = call)
}

#' Overlay a mask on the canvas
#' @inheritParams at_canvas_set_annotations
#' @param mask An `annot_mask`.
#' @param alpha Overlay opacity. Default `0.5`.
#' @family shiny
#' @return The proxy, invisibly.
#' @export
at_canvas_set_overlay <- function(proxy, mask, alpha = 0.5,
                                  call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  .check_number(alpha, min = 0, max = 1, call = call)
  uri <- .mask_data_uri(mask)
  .canvas_msg(proxy, "set_overlay", list(overlay = uri, alpha = alpha), call = call)
}

# Encode a mask preview to a coloured PNG data URI.
.mask_data_uri <- function(mask, max_dim = 1024L) {
  if (!requireNamespace("magick", quietly = TRUE)) {
    return(NULL)
  }
  pv <- at_mask_preview(mask, max_dim = max_dim)
  m <- as.matrix(pv)
  lg <- attr(pv, "legend")
  arr <- array(0, dim = c(nrow(m), ncol(m), 4L))
  if (nrow(lg) > 0L) {
    for (k in seq_len(nrow(lg))) {
      col <- grDevices::col2rgb(lg$colour[k]) / 255
      sel <- m == lg$value[k]
      arr[, , 1][sel] <- col[1]
      arr[, , 2][sel] <- col[2]
      arr[, , 3][sel] <- col[3]
      arr[, , 4][sel] <- 1
    }
  }
  im <- magick::image_read(arr)
  raw <- magick::image_write(im, format = "png")
  paste0("data:image/png;base64,", jsonlite::base64_enc(raw))
}

#' Zoom the canvas to a bounding box
#' @inheritParams at_canvas_set_annotations
#' @param bbox Optional `c(xmin, ymin, xmax, ymax)` in level-0 pixels; fits the
#'   whole image when `NULL`.
#' @family shiny
#' @return The proxy, invisibly.
#' @export
at_canvas_fit <- function(proxy, bbox = NULL, call = rlang::caller_env()) {
  .canvas_msg(proxy, "fit_bounds", list(bbox = if (is.null(bbox)) NULL else as.numeric(bbox)),
              call = call)
}
