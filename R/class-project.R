# The annot_project class: an image plus a named set of annotation layers and
# provenance. All mutators are pure: they return a modified copy and never
# change their input, and every mutation appends to the provenance edit log.

# ---- Internal constructor and helpers --------------------------------------

new_annot_project <- function(image,
                              layers = list(),
                              meta = list(),
                              provenance = list()) {
  structure(
    list(
      image      = image,
      layers     = layers,
      meta       = meta,
      provenance = provenance
    ),
    class = "annot_project"
  )
}

# Canonical 0-row layer table.
.empty_layers_tbl <- function() {
  tibble::tibble(
    name    = character(0),
    n_rois  = integer(0),
    labels  = list(),
    visible = logical(0),
    locked  = logical(0),
    z       = integer(0)
  )
}

# Coerce a layer argument to a named list keyed by layer name.
.normalize_layers <- function(layers, call = rlang::caller_env()) {
  if (inherits(layers, "annot_layer")) {
    layers <- list(layers)
  }
  if (!is.list(layers)) {
    cli::cli_abort(
      c(
        "{.arg layers} must be an {.cls annot_layer} or a list of them.",
        "x" = "You supplied {.cls {class(layers)[1]}}."
      ),
      call = call
    )
  }
  if (length(layers) == 0L) {
    return(list())
  }
  ok <- vapply(layers, inherits, logical(1), "annot_layer")
  if (!all(ok)) {
    cli::cli_abort(
      c(
        "Every element of {.arg layers} must be an {.cls annot_layer}.",
        "x" = "{cli::qty(sum(!ok))}Element{?s} at position{?s} not a layer: {.val {which(!ok)}}."
      ),
      call = call
    )
  }
  nms <- vapply(layers, `[[`, character(1), "name")
  if (anyDuplicated(nms)) {
    dup <- unique(nms[duplicated(nms)])
    cli::cli_abort(
      c("Layer names must be unique.", "x" = "Duplicated: {.val {dup}}."),
      call = call
    )
  }
  names(layers) <- nms
  layers
}

# Append an entry to the project's provenance edit log.
.log_edit <- function(project, action, detail = "") {
  entry <- list(time = .now(), action = action, detail = detail)
  project$provenance$edit_log <- c(project$provenance$edit_log, list(entry))
  project$provenance$modified <- .now()
  project
}

# All ROI identifiers across all layers.
.all_roi_ids <- function(project) {
  unlist(
    lapply(project$layers, function(L) vapply(L$rois, `[[`, character(1), "id")),
    use.names = FALSE
  )
}

# ---- Constructor -----------------------------------------------------------

#' Create an annotation project
#'
#' @param image An [annot_image] the annotations refer to.
#' @param layers An [annot_layer], a list of them, or an empty list (default).
#' @param ... Additional named project metadata (e.g. `name`, `description`).
#' @param call The calling environment, for error reporting.
#'
#' @return An [annot_project] bundling the image, layers, metadata, and
#'   provenance (creation time, `annotatR` version, R version, author, and an
#'   edit log).
#' @family projects
#' @seealso [at_add_layer()], [at_add_roi()], [at_rois()], `at_mask()`
#' @export
#' @examples
#' # An annot_image comes from at_read_image() or at_example_image():
#' # proj <- at_project(at_example_image("tissue"),
#' #                    at_layer("tissue", labels = "tissue"))
at_project <- function(image, layers = list(), ..., call = rlang::caller_env()) {
  .check_image(image, call = call)
  layers <- .normalize_layers(layers, call = call)
  provenance <- list(
    created          = .now(),
    modified         = .now(),
    annotatR_version = .pkg_version(),
    r_version        = as.character(getRversion()),
    author           = .default_author(),
    edit_log         = list()
  )
  new_annot_project(image = image, layers = layers, meta = list(...),
                    provenance = provenance)
}

# ---- Mutators (pure) -------------------------------------------------------

#' Add a layer to a project
#'
#' @param project An [annot_project].
#' @param layer An [annot_layer] with a name not already used in the project.
#' @param call The calling environment, for error reporting.
#' @return A new [annot_project] with the layer added. The input is unchanged.
#' @family projects
#' @export
at_add_layer <- function(project, layer, call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_layer(layer, call = call)
  if (layer$name %in% names(project$layers)) {
    cli::cli_abort(
      c(
        "A layer named {.val {layer$name}} already exists.",
        "i" = "Layer names must be unique within a project."
      ),
      call = call
    )
  }
  project$layers[[layer$name]] <- layer
  .log_edit(project, "add_layer", layer$name)
}

#' Remove a layer from a project
#'
#' @param project An [annot_project].
#' @param name Single string layer name.
#' @param call The calling environment, for error reporting.
#' @return A new [annot_project] without the named layer. The input is unchanged.
#' @family projects
#' @export
at_remove_layer <- function(project, name, call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(name, call = call)
  if (!name %in% names(project$layers)) {
    cli::cli_abort(
      c(
        "No layer named {.val {name}}.",
        "i" = "Available layers: {.val {names(project$layers)}}."
      ),
      call = call
    )
  }
  project$layers[[name]] <- NULL
  .log_edit(project, "remove_layer", name)
}

#' Add an ROI to a project layer
#'
#' @param project An [annot_project].
#' @param layer Single string name of the target layer.
#' @param roi An [annot_roi].
#' @param call The calling environment, for error reporting.
#' @return A new [annot_project] with the ROI added to the layer. A colliding
#'   ROI identifier is re-minted to keep identifiers unique across the project.
#'   The input is unchanged.
#' @family projects
#' @export
at_add_roi <- function(project, layer, roi, call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(layer, call = call)
  .check_roi(roi, call = call)
  if (!layer %in% names(project$layers)) {
    cli::cli_abort(
      c(
        "No layer named {.val {layer}}.",
        "i" = "Available layers: {.val {names(project$layers)}}."
      ),
      call = call
    )
  }
  if (roi$id %in% .all_roi_ids(project)) {
    roi$id <- .new_id("roi")
  }
  project$layers[[layer]] <- at_layer_add(project$layers[[layer]], roi)
  .log_edit(project, "add_roi", paste0(layer, "/", roi$id))
}

#' Remove an ROI from a project
#'
#' @param project An [annot_project].
#' @param id Single string ROI identifier.
#' @param call The calling environment, for error reporting.
#' @return A new [annot_project] without the identified ROI. Warns and returns
#'   the project unchanged if the identifier is not found.
#' @family projects
#' @export
at_remove_roi <- function(project, id, call = rlang::caller_env()) {
  .check_project(project, call = call)
  .check_string(id, call = call)
  found <- FALSE
  for (nm in names(project$layers)) {
    ids <- vapply(project$layers[[nm]]$rois, `[[`, character(1), "id")
    if (id %in% ids) {
      project$layers[[nm]] <- at_layer_remove(project$layers[[nm]], id)
      found <- TRUE
    }
  }
  if (!found) {
    cli::cli_warn("No ROI with id {.val {id}} found; nothing removed.")
    return(project)
  }
  .log_edit(project, "remove_roi", id)
}

# ---- Queries ---------------------------------------------------------------

#' Layer summary table
#'
#' @param project An [annot_project].
#' @param call The calling environment, for error reporting.
#' @return A [tibble::tibble] with one row per layer and the columns `name`
#'   (character), `n_rois` (integer), `labels` (list of character), `visible`
#'   (logical), `locked` (logical), and `z` (integer). A 0-row tibble with these
#'   columns when the project has no layers.
#' @family projects
#' @export
at_layers <- function(project, call = rlang::caller_env()) {
  .check_project(project, call = call)
  Ls <- project$layers
  if (length(Ls) == 0L) {
    return(.empty_layers_tbl())
  }
  tibble::tibble(
    name    = unname(vapply(Ls, `[[`, character(1), "name")),
    n_rois  = unname(vapply(Ls, function(L) length(L$rois), integer(1))),
    labels  = unname(lapply(Ls, `[[`, "labels")),
    visible = unname(vapply(Ls, function(L) isTRUE(L$style$visible), logical(1))),
    locked  = unname(vapply(Ls, function(L) isTRUE(L$style$locked), logical(1))),
    z       = unname(vapply(Ls, function(L) as.integer(L$style$z), integer(1)))
  )
}

#' Query the ROIs of a project
#'
#' Return a tidy table of ROIs, optionally filtered by layer and/or label.
#'
#' Coordinates in the `geometry` column, together with `area_px` and the
#' centroid, are expressed at pyramid level 0; the `level` column records the
#' level at which each ROI was originally defined.
#'
#' @param project An [annot_project].
#' @param layer Optional single layer name to filter to.
#' @param label Optional character vector of labels to filter to.
#' @param call The calling environment, for error reporting.
#'
#' @return A [tibble::tibble] with one row per ROI and, in this exact order, the
#'   columns:
#'   \describe{
#'     \item{`roi_id`}{Unique identifier (character).}
#'     \item{`layer`}{Layer name (character).}
#'     \item{`label`}{Class label (character).}
#'     \item{`geom_type`}{Geometry type, e.g. `"POLYGON"` (character).}
#'     \item{`level`}{Reference pyramid level (integer).}
#'     \item{`area_px`}{Area in level-0 pixels (double); `NA` for points/lines.}
#'     \item{`centroid_x`,`centroid_y`}{Centroid at level 0 (double).}
#'     \item{`n_vertices`}{Vertex count (integer).}
#'     \item{`created`,`modified`}{Timestamps (POSIXct).}
#'     \item{`author`}{Author (character).}
#'     \item{`source`}{Provenance source (character).}
#'     \item{`geometry`}{The `sf` geometry column (`sfc`), at level 0.}
#'   }
#'   Returns a 0-row tibble with these columns if no ROIs match.
#' @family projects
#' @seealso [at_layers()], `at_mask()`
#' @export
#' @examples
#' # proj <- at_example_project()
#' # at_rois(proj)
at_rois <- function(project, layer = NULL, label = NULL,
                    call = rlang::caller_env()) {
  .check_project(project, call = call)
  Ls <- project$layers
  if (!is.null(layer)) {
    .check_string(layer, call = call)
    if (!layer %in% names(Ls)) {
      cli::cli_abort(
        c(
          "No layer named {.val {layer}}.",
          "i" = "Available layers: {.val {names(Ls)}}."
        ),
        call = call
      )
    }
    Ls <- Ls[layer]
  }
  rois <- list()
  lyr_names <- character()
  for (nm in names(Ls)) {
    for (r in Ls[[nm]]$rois) {
      rois <- c(rois, list(r))
      lyr_names <- c(lyr_names, nm)
    }
  }
  if (!is.null(label)) {
    label <- as.character(label)
    keep <- vapply(rois, function(r) r$label %in% label, logical(1))
    rois <- rois[keep]
    lyr_names <- lyr_names[keep]
  }
  .rois_to_tbl(rois, lyr_names, image = project$image)
}

# ---- Validation and summary ------------------------------------------------

#' Validate a project's invariants
#'
#' Check that layer names are unique, ROI identifiers are unique across the
#' project, and all geometries are valid.
#'
#' @param project An [annot_project].
#' @param call The calling environment, for error reporting.
#' @return The project, invisibly, if valid; otherwise an error describing the
#'   violated invariant.
#' @family projects
#' @seealso `at_check_geometry()`
#' @export
#' @examples
#' proj <- at_validate(at_example_project())
at_validate <- function(project, call = rlang::caller_env()) {
  .check_project(project, call = call)
  nms <- names(project$layers)
  if (anyDuplicated(nms)) {
    cli::cli_abort(
      c("Layer names must be unique.",
        "x" = "Duplicated: {.val {unique(nms[duplicated(nms)])}}."),
      call = call
    )
  }
  ids <- .all_roi_ids(project)
  if (anyDuplicated(ids)) {
    cli::cli_abort(
      c("ROI identifiers must be unique across the project.",
        "x" = "Duplicated: {.val {unique(ids[duplicated(ids)])}}."),
      call = call
    )
  }
  for (nm in names(project$layers)) {
    for (r in project$layers[[nm]]$rois) {
      if (!isTRUE(sf::st_is_valid(r$geometry))) {
        cli::cli_abort(
          c("ROI {.val {r$id}} in layer {.val {nm}} has invalid geometry.",
            "i" = "Repair it with {.fn at_fix_geometry}."),
          call = call
        )
      }
    }
  }
  invisible(project)
}

#' Summarise a project
#'
#' @param project An [annot_project].
#' @param call The calling environment, for error reporting.
#' @return An `annot_summary` object: a list with `n_layers`, `n_rois`,
#'   per-label ROI counts, and total area per label.
#' @family projects
#' @export
#' @examples
#' at_summary(at_example_project())
at_summary <- function(project, call = rlang::caller_env()) {
  .check_project(project, call = call)
  roi_tbl <- at_rois(project)
  if (nrow(roi_tbl) == 0L) {
    per_label <- tibble::tibble(
      label = character(0), n = integer(0), area_px = double(0)
    )
  } else {
    per_label <- dplyr::summarise(
      dplyr::group_by(roi_tbl, .data$label),
      n = dplyr::n(),
      area_px = sum(.data$area_px, na.rm = TRUE),
      .groups = "drop"
    )
    per_label <- tibble::as_tibble(sf::st_drop_geometry(per_label))
  }
  structure(
    list(
      name      = project$meta$name %||% NA_character_,
      n_layers  = length(project$layers),
      n_rois    = nrow(roi_tbl),
      per_label = per_label
    ),
    class = "annot_summary"
  )
}

# ---- S3 methods ------------------------------------------------------------

#' @export
format.annot_project <- function(x, ...) {
  nm <- x$meta$name %||% "(unnamed)"
  n_rois <- sum(vapply(x$layers, function(L) length(L$rois), integer(1)))
  c(
    cli::format_inline("{.cls annot_project} {.field {nm}}"),
    cli::format_inline("image: {.val {basename(x$image$source)}}"),
    cli::format_inline("layers: {length(x$layers)}  |  ROIs: {n_rois}")
  )
}

#' @export
print.annot_project <- function(x, ...) {
  lines <- format(x, ...)
  if (length(x$layers) > 0L) {
    for (nm in names(x$layers)) {
      L <- x$layers[[nm]]
      lines <- c(lines, cli::format_inline(
        "  {.field {nm}}: {length(L$rois)} ROI{?s}, labels {.val {L$labels}}"
      ))
    }
  }
  cat(lines, sep = "\n")
  invisible(x)
}

#' @export
summary.annot_project <- function(object, ...) {
  at_summary(object)
}

#' @export
print.annot_summary <- function(x, ...) {
  lines <- c(
    cli::format_inline("{.cls annot_summary} {.field {x$name}}"),
    cli::format_inline("layers: {x$n_layers}  |  ROIs: {x$n_rois}")
  )
  if (nrow(x$per_label) > 0L) {
    for (i in seq_len(nrow(x$per_label))) {
      lines <- c(lines, cli::format_inline(
        "  {.val {x$per_label$label[i]}}: {x$per_label$n[i]} ROI{?s}, area {round(x$per_label$area_px[i], 1)} px"
      ))
    }
  }
  cat(lines, sep = "\n")
  invisible(x)
}
