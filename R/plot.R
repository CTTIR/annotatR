# Visualisation. Every function returns a ggplot2 object and never draws; print
# the returned object to render. Conventions: theme_minimal base, Okabe-Ito
# discrete palette, viridis continuous, coord_fixed + scale_y_reverse for
# spatial plots (image orientation), and full axis/title labels.

# Choose a display level whose largest dimension is <= max_dim, else level 0.
.display_level <- function(img, max_dim) {
  for (l in rev(seq_len(img$n_levels) - 1L)) {
    d <- img$level_dims[[l + 1L]]
    if (max(d) <= max_dim) {
      return(l)
    }
  }
  0L
}

# Map an rgb argument (band indices, or wavelengths in nm) to band indices.
.resolve_rgb <- function(img, rgb) {
  if (is.null(rgb)) {
    return(NULL)
  }
  rgb <- as.numeric(rgb)
  if (at_is_spectral(img) && any(rgb > img$n_bands)) {
    wl <- at_wavelengths(img)
    return(vapply(rgb, function(w) which.min(abs(wl - w)), integer(1)))
  }
  as.integer(rgb)
}

# Build a display data frame (x, y, and either fill hex or value) from an image.
.image_display_df <- function(img, level, bands, rgb, max_dim) {
  tile <- at_tile(img, level = level)
  nr <- dim(tile)[1]
  nc <- dim(tile)[2]
  fac <- max(1L, ceiling(max(nr, nc) / max_dim))
  ys <- seq(1L, nr, by = fac)
  xs <- seq(1L, nc, by = fac)
  tile <- tile[ys, xs, , drop = FALSE]
  nr <- dim(tile)[1]
  nc <- dim(tile)[2]
  rgb_bands <- .resolve_rgb(img, rgb)
  if (is.null(rgb_bands) && is.null(bands) && dim(tile)[3] >= 3L) {
    rgb_bands <- 1:3
  }
  norm <- function(m) {
    rng <- range(m, na.rm = TRUE)
    if (diff(rng) == 0) {
      return(matrix(0, nrow(m), ncol(m)))
    }
    (m - rng[1]) / diff(rng)
  }
  grid <- expand.grid(y = seq_len(nr), x = seq_len(nc))
  if (!is.null(rgb_bands) && length(rgb_bands) == 3L) {
    r <- norm(tile[, , rgb_bands[1]])
    g <- norm(tile[, , rgb_bands[2]])
    b <- norm(tile[, , rgb_bands[3]])
    grid$fill <- grDevices::rgb(as.vector(r), as.vector(g), as.vector(b))
    grid$mode <- "rgb"
  } else {
    b1 <- if (!is.null(bands)) bands[1] else 1L
    grid$value <- as.vector(tile[, , b1])
    grid$mode <- "single"
  }
  attr(grid, "fac") <- fac
  grid
}

#' Plot an image
#'
#' @param img An [annot_image].
#' @param level Pyramid level to display; chosen automatically when `NULL`.
#' @param bands Optional band index for single-band display.
#' @param rgb Optional length-3 vector of band indices, or wavelengths in nm for
#'   a spectral cube, for a false-colour composite.
#' @param max_dim Maximum display dimension (auto-downsampled). Default `1024`.
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object.
#' @family plots
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' at_plot_image(at_example_image("tissue"))
at_plot_image <- function(img, level = NULL, bands = NULL, rgb = NULL,
                          max_dim = 1024L, call = rlang::caller_env()) {
  .check_image(img, call = call)
  if (is.null(level)) level <- .display_level(img, max_dim)
  df <- .image_display_df(img, level, bands, rgb, max_dim)
  p <- ggplot2::ggplot(df, ggplot2::aes(x = .data$x, y = .data$y)) +
    ggplot2::scale_y_reverse() +
    ggplot2::coord_fixed() +
    ggplot2::labs(title = basename(img$source), x = "x (px)", y = "y (px)") +
    ggplot2::theme_minimal()
  if (identical(df$mode[1], "rgb")) {
    p + ggplot2::geom_raster(ggplot2::aes(fill = .data$fill)) +
      ggplot2::scale_fill_identity()
  } else {
    p + ggplot2::geom_raster(ggplot2::aes(fill = .data$value)) +
      ggplot2::scale_fill_viridis_c(name = "value")
  }
}

# Assemble an sf of a project's ROIs (level 0) for spatial plotting.
.project_sf <- function(project, layer = NULL, label = NULL) {
  rt <- at_rois(project, layer = layer, label = label)
  if (nrow(rt) == 0L) {
    return(sf::st_sf(label = character(0), layer = character(0),
                     geometry = sf::st_sfc(crs = sf::NA_crs_)))
  }
  sf::st_sf(label = rt$label, layer = rt$layer, geometry = rt$geometry)
}

# Okabe-Ito fill scale keyed to a set of labels.
.label_fill_scale <- function(labels) {
  pal <- .resolve_palette(unique(labels))
  ggplot2::scale_fill_manual(values = pal, drop = FALSE)
}

#' Plot a project's ROIs
#'
#' @param project An [annot_project].
#' @param layer,label Optional filters.
#' @param show_labels Logical; draw label text at centroids. Default `TRUE`.
#' @param alpha Fill opacity; a sensible default when `NULL`.
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object. Empty projects give a valid empty plot.
#' @family plots
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' at_plot_project(at_example_project())
at_plot_project <- function(project, layer = NULL, label = NULL,
                            show_labels = TRUE, alpha = NULL,
                            call = rlang::caller_env()) {
  .check_project(project, call = call)
  sfp <- .project_sf(project, layer, label)
  a <- alpha %||% 0.4
  p <- ggplot2::ggplot(sfp) +
    ggplot2::scale_y_reverse() +
    ggplot2::labs(title = project$meta$name %||% "project", x = "x (px)", y = "y (px)") +
    ggplot2::theme_minimal()
  if (nrow(sfp) > 0L) {
    p <- p + ggplot2::geom_sf(ggplot2::aes(fill = .data$label), alpha = a) +
      .label_fill_scale(sfp$label)
    if (show_labels) {
      cent <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(sfp)))
      lab_df <- data.frame(x = cent[, 1], y = cent[, 2], label = sfp$label)
      p <- p + ggplot2::geom_text(data = lab_df,
                                  ggplot2::aes(x = .data$x, y = .data$y, label = .data$label),
                                  size = 3, colour = "black")
    }
  }
  p
}

#' Plot a mask
#'
#' @param mask An `annot_mask`.
#' @param legend Logical; show the fill legend. Default `TRUE`.
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object.
#' @family plots
#' @export
#' @examples
#' at_plot_mask(at_mask(at_example_project(), "labelled"))
at_plot_mask <- function(mask, legend = TRUE, call = rlang::caller_env()) {
  .check_class(mask, "annot_mask", call = call)
  plot(mask, legend = legend)
}

#' Plot spectra
#'
#' @param spectra The long tibble from [at_extract_spectrum()] or [at_extract()].
#' @param colour_by One of `"label"`, `"roi_id"`, or `"layer"`.
#' @param ribbon Logical; draw a min-max ribbon per colour group.
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object.
#' @family plots
#' @export
at_plot_spectrum <- function(spectra, colour_by = c("label", "roi_id", "layer"),
                             ribbon = TRUE, call = rlang::caller_env()) {
  colour_by <- .check_choice(colour_by, c("label", "roi_id", "layer"), call = call)
  spectra <- spectra[!is.na(spectra$wavelength), , drop = FALSE]
  p <- ggplot2::ggplot(spectra, ggplot2::aes(x = .data$wavelength, y = .data$value,
                                             colour = .data[[colour_by]],
                                             group = .data$roi_id)) +
    ggplot2::labs(title = "Spectra", x = "wavelength (nm)", y = "value",
                  colour = colour_by) +
    ggplot2::theme_minimal()
  if (nrow(spectra) > 0L) {
    p <- p + ggplot2::geom_line()
  }
  p
}

#' Plot ROIs overlaid on the image
#'
#' @param project An [annot_project].
#' @param img An [annot_image]; the project's image by default.
#' @param layer Optional layer filter.
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object with the image and ROI outlines.
#' @family plots
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' at_plot_overlay(at_example_project())
at_plot_overlay <- function(project, img = NULL, layer = NULL,
                            call = rlang::caller_env()) {
  .check_project(project, call = call)
  if (is.null(img)) img <- project$image
  base <- at_plot_image(img, call = call)
  rt <- at_rois(project, layer = layer)
  if (nrow(rt) > 0L) {
    # Draw outlines with geom_path (not geom_sf) to keep coord_fixed consistent
    # with the raster and avoid a coordinate-system clash.
    co <- sf::st_coordinates(rt$geometry)
    lcols <- setdiff(colnames(co), c("X", "Y"))
    feat <- co[, lcols[length(lcols)]] # last hierarchy column = feature index
    group_id <- apply(co[, lcols, drop = FALSE], 1L, paste, collapse = "_")
    poly_df <- data.frame(
      x = co[, "X"], y = co[, "Y"], group = group_id, label = rt$label[feat]
    )
    base <- base +
      ggplot2::geom_path(data = poly_df,
                         ggplot2::aes(x = .data$x, y = .data$y,
                                      group = .data$group, colour = .data$label),
                         linewidth = 0.7, inherit.aes = FALSE) +
      ggplot2::labs(colour = "label")
  }
  base
}

#' Plot a project summary
#'
#' @param project An [annot_project].
#' @param call The calling environment, for error reporting.
#' @return A [ggplot2::ggplot] object of per-label ROI area distributions.
#' @family plots
#' @export
at_plot_summary <- function(project, call = rlang::caller_env()) {
  .check_project(project, call = call)
  rt <- at_rois(project)
  rt <- sf::st_drop_geometry(rt)
  p <- ggplot2::ggplot(rt, ggplot2::aes(x = .data$label, y = .data$area_px,
                                        fill = .data$label)) +
    ggplot2::labs(title = "ROI area by label", x = "label", y = "area (px)") +
    ggplot2::theme_minimal() +
    ggplot2::theme(legend.position = "none")
  if (nrow(rt) > 0L) {
    p <- p + ggplot2::geom_boxplot(alpha = 0.5) +
      ggplot2::geom_jitter(width = 0.15, height = 0, size = 1) +
      .label_fill_scale(rt$label)
  }
  p
}

#' Plot generic for annotatR objects
#'
#' @param x An [annot_image], [annot_project], or `annot_mask`.
#' @param ... Passed to the specific plot function.
#' @return A [ggplot2::ggplot] object.
#' @family plots
#' @export
#' @examples
#' at_plot(at_example_project())
at_plot <- function(x, ...) {
  if (inherits(x, "annot_image")) return(at_plot_image(x, ...))
  if (inherits(x, "annot_project")) return(at_plot_project(x, ...))
  if (inherits(x, "annot_mask")) return(at_plot_mask(x, ...))
  if (inherits(x, "annot_layer")) {
    rt <- at_layer_rois(x)
    sfp <- if (nrow(rt) > 0L) {
      sf::st_sf(label = rt$label, geometry = rt$geometry)
    } else {
      sf::st_sf(label = character(0), geometry = sf::st_sfc(crs = sf::NA_crs_))
    }
    p <- ggplot2::ggplot(sfp) +
      ggplot2::scale_y_reverse() +
      ggplot2::labs(title = x$name, x = "x (px)", y = "y (px)") +
      ggplot2::theme_minimal()
    if (nrow(sfp) > 0L) {
      p <- p + ggplot2::geom_sf(ggplot2::aes(fill = .data$label), alpha = 0.4) +
        .label_fill_scale(sfp$label)
    }
    return(p)
  }
  cli::cli_abort("No {.fn at_plot} method for {.cls {class(x)[1]}}.")
}

#' @exportS3Method ggplot2::autoplot
autoplot.annot_project <- function(object, ...) at_plot_project(object, ...)

#' @exportS3Method ggplot2::autoplot
autoplot.annot_image <- function(object, ...) at_plot_image(object, ...)

#' @exportS3Method ggplot2::autoplot
autoplot.annot_mask <- function(object, ...) at_plot_mask(object, ...)

#' @exportS3Method ggplot2::autoplot
autoplot.annot_layer <- function(object, ...) at_plot(object, ...)
