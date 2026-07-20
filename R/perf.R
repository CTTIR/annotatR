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
  paste(img$source, img$backend, level,
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

# Is `geom` (an sfg) an axis-aligned rectangle: a single ring with exactly two
# distinct x and two distinct y values?
.is_axis_aligned_rect <- function(geom) {
  if (length(unclass(geom)) != 1L) {
    return(FALSE)
  }
  ring <- geom[[1]]
  length(unique(round(ring[, 1], 9))) == 2L &&
    length(unique(round(ring[, 2], 9))) == 2L
}

# Fast, exact cover for rectangles and points (touches = FALSE only). Returns a
# logical [height, width] matrix identical to the general rasteriser, or NULL
# when no fast path applies. Uses the same half-open [lower, upper) convention:
# a pixel centre at k - 0.5 is covered when lower <= k - 0.5 < upper.
.cover_shortcircuit <- function(geom, dims) {
  type <- as.character(sf::st_geometry_type(sf::st_sfc(geom)))
  width <- as.integer(dims[1])
  height <- as.integer(dims[2])
  if (type == "POINT") {
    co <- as.numeric(unclass(geom))
    j <- as.integer(floor(co[1] - 1e-7)) + 1L
    i <- as.integer(floor(co[2] - 1e-7)) + 1L
    m <- matrix(FALSE, height, width)
    if (i >= 1L && i <= height && j >= 1L && j <= width) {
      m[i, j] <- TRUE
    }
    return(m)
  }
  if (type == "POLYGON" && .is_axis_aligned_rect(geom)) {
    ring <- geom[[1]]
    xmin <- min(ring[, 1]); xmax <- max(ring[, 1])
    ymin <- min(ring[, 2]); ymax <- max(ring[, 2])
    j1 <- max(1L, as.integer(ceiling(xmin + 0.5)))
    j2 <- min(width, as.integer(ceiling(xmax - 0.5)))
    i1 <- max(1L, as.integer(ceiling(ymin + 0.5)))
    i2 <- min(height, as.integer(ceiling(ymax - 0.5)))
    m <- matrix(FALSE, height, width)
    if (j1 <= j2 && i1 <= i2) {
      m[i1:i2, j1:j2] <- TRUE
    }
    return(m)
  }
  NULL
}
