# The annot_layer class: a named collection of ROIs sharing a controlled label
# vocabulary and a visual style.

# ---- Internal constructor --------------------------------------------------

new_annot_layer <- function(name,
                            rois = list(),
                            labels = character(),
                            style = at_style(),
                            meta = list()) {
  structure(
    list(
      name   = as.character(name),
      rois   = rois,
      labels = as.character(labels),
      style  = style,
      meta   = meta
    ),
    class = "annot_layer"
  )
}

#' Layer style
#'
#' Construct a style specification for an [annot_layer].
#'
#' @param colour Either `NULL` (default; the Okabe-Ito colourblind-safe palette
#'   is cycled over the layer's labels), a single colour recycled across labels,
#'   or a named character vector mapping labels to colours. The style is stored
#'   with the resolved mapping so colours are stable across sessions.
#' @param fill_alpha Fill opacity in `[0, 1]`. Default `0.3`.
#' @param stroke_width Stroke width in pixels. Default `2`.
#' @param visible Logical; whether the layer is drawn. Default `TRUE`.
#' @param locked Logical; whether the layer is protected from edits. Default
#'   `FALSE`.
#' @param z Integer draw order (higher is drawn later, on top). Affects mask
#'   overlap resolution. Default `1`.
#' @param call The calling environment, for error reporting.
#'
#' @return A named list of class `annot_style`.
#' @family layers
#' @export
#' @examples
#' at_style(fill_alpha = 0.5, z = 2)
at_style <- function(colour = NULL, fill_alpha = 0.3, stroke_width = 2,
                     visible = TRUE, locked = FALSE, z = 1L,
                     call = rlang::caller_env()) {
  .check_number(fill_alpha, min = 0, max = 1, call = call)
  .check_number(stroke_width, min = 0, call = call)
  .check_flag(visible, call = call)
  .check_flag(locked, call = call)
  z <- .check_count(z, call = call)
  if (!is.null(colour) && !is.character(colour)) {
    cli::cli_abort(
      c(
        "{.arg colour} must be `NULL` or a character vector of colours.",
        "x" = "You supplied {.cls {class(colour)[1]}}."
      ),
      call = call
    )
  }
  structure(
    list(
      colour = colour, fill_alpha = fill_alpha, stroke_width = stroke_width,
      visible = visible, locked = locked, z = z
    ),
    class = "annot_style"
  )
}

#' Create a layer
#'
#' @param name Single string layer name (unique within a project).
#' @param labels Character vector; the controlled label vocabulary for the layer.
#' @param style An `annot_style`, from [at_style()].
#' @param ... Additional named metadata stored on the layer.
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_layer] with no ROIs and a resolved colour mapping.
#' @family layers
#' @seealso [at_style()], [at_layer_add()]
#' @export
#' @examples
#' lyr <- at_layer("tumour", labels = c("tumour", "stroma"))
#' at_layer_n(lyr)
at_layer <- function(name, labels = character(), style = at_style(), ...,
                     call = rlang::caller_env()) {
  .check_string(name, call = call)
  .check_class(style, "annot_style", call = call)
  labels <- unique(as.character(labels))
  style$colour <- .resolve_palette(labels, style$colour)
  new_annot_layer(name = name, rois = list(), labels = labels, style = style,
                  meta = list(...))
}

#' Add an ROI to a layer
#'
#' @param layer An [annot_layer].
#' @param roi An [annot_roi].
#' @param call The calling environment, for error reporting.
#'
#' @return A new [annot_layer] with the ROI appended. The label vocabulary and
#'   colour mapping are extended if the ROI introduces a new label. A colliding
#'   ROI identifier is re-minted to preserve uniqueness. The input is unchanged.
#' @family layers
#' @export
#' @examples
#' lyr <- at_layer("tumour", labels = "tumour")
#' lyr <- at_layer_add(lyr, at_roi_rect(0, 0, 10, 10, label = "tumour"))
#' at_layer_n(lyr)
at_layer_add <- function(layer, roi, call = rlang::caller_env()) {
  .check_layer(layer, call = call)
  .check_roi(roi, call = call)
  existing <- vapply(layer$rois, `[[`, character(1), "id")
  if (roi$id %in% existing) {
    roi$id <- .new_id("roi")
  }
  if (!roi$label %in% layer$labels) {
    layer$labels <- c(layer$labels, roi$label)
    layer$style$colour <- .resolve_palette(layer$labels, layer$style$colour)
  }
  layer$rois <- c(layer$rois, list(roi))
  layer
}

#' Remove an ROI from a layer
#'
#' @param layer An [annot_layer].
#' @param id Single string ROI identifier.
#' @param call The calling environment, for error reporting.
#' @return A new [annot_layer] without the identified ROI. Warns if the ROI is
#'   not present and returns the layer unchanged.
#' @family layers
#' @export
at_layer_remove <- function(layer, id, call = rlang::caller_env()) {
  .check_layer(layer, call = call)
  .check_string(id, call = call)
  ids <- vapply(layer$rois, `[[`, character(1), "id")
  hit <- which(ids == id)
  if (length(hit) == 0L) {
    cli::cli_warn("No ROI with id {.val {id}} in layer {.val {layer$name}}; nothing removed.")
    return(layer)
  }
  layer$rois <- layer$rois[-hit]
  layer
}

#' Layer ROI table
#'
#' @param layer An [annot_layer].
#' @param image Optional [annot_image] for accurate level-0 coordinate transforms.
#' @param call The calling environment, for error reporting.
#' @return An ROI table (see [at_rois()] for the column contract). A 0-row table
#'   with the same columns when the layer has no ROIs.
#' @family layers
#' @export
at_layer_rois <- function(layer, image = NULL, call = rlang::caller_env()) {
  .check_layer(layer, call = call)
  .rois_to_tbl(layer$rois, rep(layer$name, length(layer$rois)), image = image)
}

#' Number of ROIs in a layer
#'
#' @param layer An [annot_layer].
#' @param call The calling environment, for error reporting.
#' @return An integer scalar.
#' @family layers
#' @export
at_layer_n <- function(layer, call = rlang::caller_env()) {
  .check_layer(layer, call = call)
  length(layer$rois)
}

# ---- S3 methods ------------------------------------------------------------

#' @export
format.annot_layer <- function(x, ...) {
  c(
    cli::format_inline("{.cls annot_layer} {.field {x$name}}"),
    cli::format_inline(
      "ROIs: {length(x$rois)}  |  labels: {.val {x$labels}}"
    ),
    cli::format_inline(
      "visible: {x$style$visible}  |  locked: {x$style$locked}  |  z: {x$style$z}"
    )
  )
}

#' @export
print.annot_layer <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}
