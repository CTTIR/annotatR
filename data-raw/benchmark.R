# Performance benchmarks (not shipped). Run with: Rscript data-raw/benchmark.R
suppressMessages(devtools::load_all(quiet = TRUE))

bench <- function(expr, times = 5L) {
  e <- substitute(expr)
  env <- parent.frame()
  # eval() of a captured expression is the standard benchmarking idiom; the
  # expressions here are trusted, from this script only.
  ts <- replicate(times, system.time(eval(e, env))["elapsed"])
  round(median(ts) * 1000, 1) # ms
}

cat("== Tile cache (2048x2048x3 in-memory image) ==\n")
arr <- array(runif(2048 * 2048 * 3), dim = c(2048, 2048, 3))
big <- new_annot_image("big.tif", "raster", c(2048L, 2048L), 1L,
                       list(c(2048L, 2048L)), 3L, handle = list(data = arr))
.tile_cache_clear()
cold <- bench({ .tile_cache_clear(); at_tile(big) }, 5L)
invisible(at_tile(big)) # warm the cache
warm <- bench(at_tile(big), 20L)
cat(sprintf("  cold (tile_fn slice): %s ms;  warm (cache hit): %s ms;  speedup %.1fx\n",
            cold, warm, cold / max(warm, 0.01)))

cat("== Mask rasterisation (rectangle) ==\n")
r <- at_roi_rect(100, 100, 1900, 1900, label = "a")
sc <- bench(at_mask(r, "binary", dims = c(2048, 2048)), 5L)
# force the general path by using a near-rectangle polygon (not axis-aligned)
poly <- at_roi_polygon(rbind(c(100, 100), c(1900, 101), c(1900, 1900), c(100, 1900)), label = "a")
gen <- bench(at_mask(poly, "binary", dims = c(2048, 2048)), 5L)
cat(sprintf("  rect short-circuit: %s ms;  general polygon: %s ms\n", sc, gen))

cat("== Mask (100 ROIs, 2048x2048, binary) ==\n")
lyr <- at_layer("l")
set.seed(1)
for (i in seq_len(100)) {
  x <- runif(1, 0, 1900); y <- runif(1, 0, 1900)
  lyr <- at_layer_add(lyr, at_roi_circle(x, y, 40, label = "a"))
}
proj100 <- at_project(big, lyr)
cat(sprintf("  at_mask 100 ROIs: %s ms\n", bench(at_mask(proj100, "binary"), 3L)))

cat("== Extraction (100 ROIs, 3-band) ==\n")
cat(sprintf("  at_extract mean: %s ms\n", bench(at_extract(proj100, stat = "mean"), 3L)))

cat("== at_read_image (tissue PNG) ==\n")
cat(sprintf("  read: %s ms\n", bench({ .tile_cache_clear(); at_example_image("tissue") }, 5L)))
