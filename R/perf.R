# Performance internals: an LRU tile cache and fast-path mask rasterisation for
# axis-aligned rectangles and points. None of this is exported.

# ---- Tile cache ------------------------------------------------------------

.tile_cache <- new.env(parent = emptyenv())
.tile_cache$store <- list()
.tile_cache$order <- character()
.tile_cache$bytes <- 0

# Reset the tile cache (used by tests and available to users indirectly).
.tile_cache_clear <- function() {
  .tile_cache$store <- list()
  .tile_cache$order <- character()
  .tile_cache$bytes <- 0
  invisible(NULL)
}

.tile_cache_limit <- function() {
  getOption("annotatR.cache_size", default = 512 * 1024^2)
}

# A cache key for a tile request.
.tile_key <- function(img, level, xrange, yrange, bands) {
  descriptor <- img$source_descriptor
  source <- descriptor$path %||% img$source
  backend <- descriptor$backend %||% img$backend
  options <- descriptor$options_identity %||% ""
  identity <- img$cache_identity %||% .new_identity_id("image")
  paste(source, backend, options, identity, level,
        paste(xrange, collapse = "-"), paste(yrange, collapse = "-"),
        paste(bands, collapse = ","), sep = "|")
}

.tile_cache_get <- function(key) {
  if (is.null(.tile_cache$store[[key]])) {
    return(NULL)
  }
  # Move to most-recently-used.
  .tile_cache$order <- c(setdiff(.tile_cache$order, key), key)
  .tile_cache$store[[key]]
}

.tile_cache_put <- function(key, arr) {
  sz <- as.numeric(utils::object.size(arr))
  if (sz > .tile_cache_limit()) {
    return(invisible(NULL)) # too big to cache
  }
  if (!is.null(.tile_cache$store[[key]])) {
    .tile_cache$bytes <- .tile_cache$bytes - as.numeric(utils::object.size(.tile_cache$store[[key]]))
  }
  .tile_cache$store[[key]] <- arr
  .tile_cache$order <- c(setdiff(.tile_cache$order, key), key)
  .tile_cache$bytes <- .tile_cache$bytes + sz
  # Evict least-recently-used until under the limit.
  while (.tile_cache$bytes > .tile_cache_limit() && length(.tile_cache$order) > 1L) {
    victim <- .tile_cache$order[1]
    .tile_cache$bytes <- .tile_cache$bytes - as.numeric(utils::object.size(.tile_cache$store[[victim]]))
    .tile_cache$store[[victim]] <- NULL
    .tile_cache$order <- .tile_cache$order[-1]
  }
  invisible(NULL)
}

# ---- Mask rasterisation fast paths -----------------------------------------

# Is `geom` a closed ring containing exactly the four distinct corners of an
# axis-aligned rectangle, traversed by axis-aligned edges? Coordinate rounding
# would incorrectly promote narrow/skew polygons, so use the stored coordinates.
.is_axis_aligned_rect <- function(geom) {
  if (!inherits(geom, "POLYGON") || length(geom) != 1L) return(FALSE)
  ring <- geom[[1]]
  if (nrow(ring) != 5L || !all(is.finite(ring[, 1:2])) ||
      !all(ring[1, 1:2] == ring[5, 1:2])) return(FALSE)
  corners <- ring[1:4, 1:2, drop = FALSE]
  if (nrow(unique(corners)) != 4L || length(unique(corners[, 1])) != 2L ||
      length(unique(corners[, 2])) != 2L) return(FALSE)
  edges <- ring[2:5, 1:2, drop = FALSE] - ring[1:4, 1:2, drop = FALSE]
  all(xor(edges[, 1] == 0, edges[, 2] == 0))
}

# Inclusive matrix indices whose centres fall in [lower, upper), clamped before
# integer conversion so distant off-image coordinates cannot overflow integers.
.centre_range <- function(lower, upper, size, origin = 0) {
  # Subtract before rounding: adding .5 to the next double above .5 would
  # round down to 1 and incorrectly include that boundary centre.
  as.integer(c(max(1, min(size + 1, ceiling(lower - 0.5) + 1 - origin)),
               max(0, min(size, ceiling(upper - 0.5) - origin))))
}

# Fast centre coverage for proven rectangles, and half-open containing cells
# for points. Returns NULL when the general polygon/engine path is required.
.cover_shortcircuit <- function(geom, dims, origin = c(0, 0)) {
  width <- as.integer(dims[1])
  height <- as.integer(dims[2])
  if (inherits(geom, "POINT") || inherits(geom, "MULTIPOINT")) {
    co <- if (inherits(geom, "POINT")) matrix(unclass(geom), nrow = 1L) else unclass(geom)
    m <- matrix(FALSE, height, width)
    if (nrow(co)) {
      j <- floor(co[, 1]) + 1 - origin[1]
      i <- floor(co[, 2]) + 1 - origin[2]
      keep <- is.finite(i) & is.finite(j) & i >= 1 & i <= height & j >= 1 & j <= width
      m[cbind(i[keep], j[keep])] <- TRUE
    }
    return(m)
  }
  if (.is_axis_aligned_rect(geom)) {
    ring <- geom[[1]]
    x <- .centre_range(min(ring[, 1]), max(ring[, 1]), width, origin[1])
    y <- .centre_range(min(ring[, 2]), max(ring[, 2]), height, origin[2])
    m <- matrix(FALSE, height, width)
    if (x[1] <= x[2] && y[1] <= y[2]) m[y[1]:y[2], x[1]:x[2]] <- TRUE
    return(m)
  }
  NULL
}
