# Interoperability

![annotatR logo](../reference/figures/logo.png)

Annotations are only useful if they can leave the tool that made them.
annotatR stores every region of interest as a validated simple-feature
geometry in image pixel coordinates, with an explicit pyramid level
attached, which makes it straightforward to hand work off to a viewer
such as QuPath, to a GIS-flavoured GeoJSON consumer, or to a Python
segmentation pipeline, and to take the results back again. Because the
geometry model is the same one used internally, an export followed by an
import is a genuine round-trip rather than a lossy approximation, and
this vignette shows a live one for each format so you can see that
labels, identities, and coordinates survive intact.

A guiding principle runs through all four formats below: the coordinate
convention never changes silently. Coordinates are written in image
pixels unless you deliberately ask otherwise, so a polygon you exported
lands back on exactly the same pixels when you read it in.

We use the bundled example project throughout: three labelled rectangles
on a small tissue raster.

``` r

proj <- at_example_project()
at_rois(proj)[, c("roi_id", "layer", "label", "geom_type", "area_px")]
#> # A tibble: 3 × 5
#>   roi_id        layer   label    geom_type area_px
#>   <chr>         <chr>   <chr>    <chr>       <dbl>
#> 1 roi_000000001 regions tumour   POLYGON     19600
#> 2 roi_000000002 regions necrosis POLYGON     72704
#> 3 roi_000000003 regions stroma   POLYGON     34200
```

## GeoJSON

[`at_write_geojson()`](https://cttir.github.io/annotatR/reference/at_write_geojson.md)
serialises a project to a standard `FeatureCollection`. Each ROI becomes
one `Feature` whose `geometry` is the pixel-coordinate polygon and whose
`properties` carry the full annotatR schema: `roi_id`, `layer`, `label`,
`level`, `author`, `created`, `modified`, `source`, the writing
`annotatR_version`, and any free-form `attributes`. Keeping the schema
explicit is what lets a file survive a return trip.

``` r

gj <- tempfile(fileext = ".geojson")
at_write_geojson(proj, gj)
cat(readLines(gj)[1:22], sep = "\n")
#> {
#>   "type": "FeatureCollection",
#>   "features": [
#>     {
#>       "type": "Feature",
#>       "id": "roi_000000001",
#>       "geometry": {
#>         "type": "Polygon",
#>         "coordinates": [
#>           [
#>             [120, 150],
#>             [260, 150],
#>             [260, 290],
#>             [120, 290],
#>             [120, 150]
#>           ]
#>         ]
#>       },
#>       "properties": {
#>         "roi_id": "roi_000000001",
#>         "layer": "regions",
#>         "label": "tumour",
```

The `roi_id` is preserved verbatim, so an ROI keeps its identity across
the boundary and you can join exported measurements back to the original
annotation. Reading the file back with
[`at_read_geojson()`](https://cttir.github.io/annotatR/reference/at_read_geojson.md)
reconstructs one `annot_layer` per distinct `layer` property. We rebuild
a project on the original image and check that the labels came through
intact.

``` r

back <- at_read_geojson(gj)
imported <- at_project(proj$image, back[["regions"]])
identical(sort(at_rois(proj)$label), sort(at_rois(imported)$label))
#> [1] TRUE
```

### The `flip_y` option

annotatR’s convention is image orientation: the origin is top-left and
*y* increases downward. Many GIS tools instead expect *y* to increase
upward. Set `flip_y = TRUE` to write coordinates in that upward
convention; the y-axis is mirrored about the image height. If you write
flipped, you must read flipped, supplying the same `height` so the
inversion is undone:

``` r

h <- at_dims(proj$image)[2]
gj_flip <- tempfile(fileext = ".geojson")
at_write_geojson(proj, gj_flip, flip_y = TRUE)
regained <- at_read_geojson(gj_flip, flip_y = TRUE, height = h)
identical(sort(at_rois(at_project(proj$image, regained[["regions"]]))$centroid_y),
          sort(at_rois(proj)$centroid_y))
#> [1] TRUE
```

Leave `flip_y` at its default `FALSE` when exchanging with other
image-coordinate tools (including QuPath and annotatR itself); reach for
it only when a downstream consumer explicitly wants a cartesian,
bottom-left origin.

## QuPath

QuPath reads and writes its own GeoJSON dialect.
[`at_write_qupath()`](https://cttir.github.io/annotatR/reference/at_write_qupath.md)
emits `annotation` objects (or `detection` for mask-derived ROIs), maps
each ROI’s label to a `classification.name`, records the lock state as
`isLocked`, and packs the layer colour into a `colorRGB` field. On the
way back,
[`at_read_qupath()`](https://cttir.github.io/annotatR/reference/at_read_qupath.md)
restores those classifications as labels; any feature whose
classification is `null` is imported under the label `"unclassified"`
rather than being dropped.

``` r

qp <- tempfile(fileext = ".geojson")
at_write_qupath(proj, qp)
grep("name|colorRGB", readLines(qp), value = TRUE)[1:2]
#> [1] "          \"name\": \"tumour\","  "          \"colorRGB\": -6710887"
```

### The colour gotcha

QuPath stores a classification colour as a **signed** 32-bit integer
packed as `0xFFRRGGBB`. The `0xFF` alpha byte pushes most colours past
`2^31`, so they wrap around to negative values: the grey `#999999` above
serialises as `-6710887`, not a friendly positive number. annotatR
handles the modular arithmetic for you in both directions, so you never
touch the raw integer, but it is worth knowing why the field looks odd.
Reading the file back recovers the hex colours onto the layer style:

``` r

lyr <- at_read_qupath(qp)
lyr$style$colour
#>    tumour  necrosis    stroma 
#> "#999999" "#E69F00" "#56B4E9"
```

## Masks for Python

For pixel-level pipelines the exchange currency is a raster mask, not a
polygon.
[`at_write_mask()`](https://cttir.github.io/annotatR/reference/at_write_mask.md)
writes an integer TIFF alongside a self-describing `<path>.legend.json`
sidecar that records the mask type, level, dimensions, and one entry per
class (`value`, `label`, `layer`, `roi_id`, `n_px`, `colour`). The
sidecar is what turns an anonymous grid of integers into something a
downstream model can interpret without guessing which value meant which
class, and it travels with the raster so the mapping is never lost.

``` r

m <- at_mask(proj, type = "labelled")
mp <- tempfile(fileext = ".tiff")
at_write_mask(m, mp)
cat(readLines(paste0(mp, ".legend.json"))[1:14], sep = "\n")
#> {
#>   "annotatR_version": "0.1.0",
#>   "created": "2026-08-22T13:05:40+0000",
#>   "mask_type": "labelled",
#>   "level": 0,
#>   "dims": [512, 512],
#>   "source_project": "example",
#>   "legend": [
#>     {
#>       "value": 1,
#>       "label": "tumour",
#>       "layer": "regions",
#>       "roi_id": "roi_000000001",
#>       "n_px": 19600,
```

Here we used a `"labelled"` mask, where each ROI gets its own integer; a
`"binary"` mask collapses everything to foreground and background, and a
`"multiclass"` mask shares one integer per label. Whichever you choose,
the legend describes exactly what the pixels mean. On the Python side,
read the TIFF as an integer array and load the legend to map values back
to labels. This chunk is illustrative and is not run when the vignette
is built.

``` python
import json
import numpy as np
import tifffile

mask = tifffile.imread("mask.tiff")
with open("mask.tiff.legend.json") as f:
    legend = json.load(f)

labels = {e["value"]: e["label"] for e in legend["legend"]}
for value, label in labels.items():
    print(label, int(np.sum(mask == value)), "px")
```

## CSV and WKT

For spreadsheet users and pipelines that would rather not parse JSON,
[`at_write_rois_csv()`](https://cttir.github.io/annotatR/reference/at_write_rois_csv.md)
produces one row per ROI with the geometry in a Well-Known Text
`geometry` column, plus the metadata fields.
[`at_read_rois_csv()`](https://cttir.github.io/annotatR/reference/at_read_rois_csv.md)
parses any CSV with at least `label` and `geometry` columns back into a
layer.

``` r

csv <- tempfile(fileext = ".csv")
at_write_rois_csv(proj, csv)
lyr_csv <- at_read_rois_csv(csv, layer_name = "regions")
at_rois(at_project(proj$image, lyr_csv))[, c("label", "geom_type", "area_px")]
#> # A tibble: 3 × 3
#>   label    geom_type area_px
#>   <chr>    <chr>       <dbl>
#> 1 tumour   POLYGON     19600
#> 2 necrosis POLYGON     72704
#> 3 stroma   POLYGON     34200
```

Because WKT is understood by PostGIS, `sf`, Shapely, and most spatial
databases, the CSV is often the shortest path into a wider geospatial
stack.

For the complete list of import and export helpers, see the reference
index on the package website.

## Use of LLM tools

Portions of this package were prepared with assistance from large
language model tooling for narrowly defined, non-authorial tasks:
copyediting, prose smoothing, Markdown/LaTeX formatting, scaffolding of
boilerplate files (CI configs, build scripts), code refactoring. The
tools used were Chat AI, the LLM service of KISSKI (GWDG), and a
self-hosted Mistral Small (24B, Apache-2.0) run locally via Ollama and
the ollamar R package — local inference only, with no data sent to third
parties for the self-hosted model.
