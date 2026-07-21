# The annotation model

![annotatR logo](../reference/figures/logo.png)

annotatR represents an annotation as a small hierarchy of plain R
objects, each a validated layer built on the one below. This vignette
describes that model: the pixel coordinate system every object shares,
the four nested classes, how geometric validity is checked and repaired,
and how coordinates move between pyramid levels. These few conventions
are enough to use the rest of the package with confidence.

## The coordinate system

Every coordinate in annotatR is an image pixel coordinate. The origin
sits at the top-left corner of the image, `x` increases to the right,
and `y` increases *downward* – the raster convention used by cameras,
microscopes, and most image libraries. This is the mirror image of the
GIS convention, in which `y` increases upward. When exchanging geometry
with GIS-oriented tooling, flip at the boundary with
[`at_flip_y()`](https://cttir.github.io/annotatR/reference/at_flip_y.md).

A pixel is a unit cell, not a point. Pixel `(i, j)` – row `i`, column
`j`, both one-based – covers the half-open square `[j-1, j) x [i-1, i)`,
so its centre lies at `(j - 0.5, i - 0.5)`. Membership follows that
centre: a pixel belongs to a region when its centre falls inside the
polygon, resolved with a half-open `[lower, upper)` tie rule along the
lower and left edges. This single convention keeps rasterisation
deterministic and stops abutting regions from double-counting a shared
border.

            x increases  --->
          0     1     2     3
        0 +-----+-----+-----+
          |     |     |     |     pixel (row 2, col 2)
        1 +-----+-----+-----+     covers [1, 2) x [1, 2)
     y  |     |  o  |     |       centre = (1.5, 1.5)   <- "o"
     |  |     | 1.5 |     |
     v  2 +-----+-----+-----+
          |     |     |     |
        3 +-----+-----+-----+

A rectangle spanning columns and rows 2–3 makes the rule concrete.
Testing the centres of the four pixels along the diagonal, only those
whose centre falls inside are matched:

``` r

sq <- at_roi_rect(1, 1, 3, 3, label = "cell")
at_roi_contains(sq, x = c(0.5, 1.5, 2.5, 3.5), y = c(0.5, 1.5, 2.5, 3.5))
#> [1] FALSE  TRUE  TRUE FALSE
```

## The object hierarchy

Annotations are built from four nested classes: `annot_roi` -\>
`annot_layer` -\> `annot_project` -\> `annot_session`.

An **`annot_roi`** is a single region of interest: an `sf` geometry (a
point, polygon, ellipse, and so on) stored in pixel coordinates at a
declared pyramid level, together with a label, a unique identifier, and
provenance.

``` r

rect <- at_roi_rect(120, 150, 260, 290, label = "tumour")
rect
#> <annot_roi> tumour (POLYGON)
#> id: "roi_000000002"  |  level: 0  |  source: manual
#> bbox: [120, 150] - [260, 290]
at_roi_area(rect)
#> [1] 19600
```

An **`annot_layer`** groups ROIs that share a controlled label
vocabulary and a drawing style. Layers are the unit of visibility,
locking, and z-order. Adding an ROI never mutates the input; it returns
an extended copy.

``` r

regions <- at_layer("regions", labels = c("tumour", "stroma"))
regions <- at_layer_add(regions, rect)
regions <- at_layer_add(regions, at_roi_circle(400, 120, r = 40, label = "stroma"))
regions
#> <annot_layer> regions
#> ROIs: 2  |  labels: "tumour" and "stroma"
#> visible: TRUE  |  locked: FALSE  |  z: 1
```

An **`annot_project`** binds one image to a named set of layers and
records provenance. It is the object you query, validate, rasterise, and
export.
[`at_rois()`](https://cttir.github.io/annotatR/reference/at_rois.md)
returns a tidy table in which coordinates, areas, and centroids are
expressed at level 0, while the `level` column preserves where each ROI
was originally defined.

``` r

img  <- at_example_image("tissue")
proj <- at_project(img, regions, name = "demo")
at_layers(proj)
#> # A tibble: 1 × 6
#>   name    n_rois labels    visible locked     z
#>   <chr>    <int> <list>    <lgl>   <lgl>  <int>
#> 1 regions      2 <chr [2]> TRUE    FALSE      1
at_rois(proj)[, c("roi_id", "layer", "label", "geom_type", "level", "area_px")]
#> # A tibble: 2 × 6
#>   roi_id        layer   label  geom_type level area_px
#>   <chr>         <chr>   <chr>  <chr>     <int>   <dbl>
#> 1 roi_000000002 regions tumour POLYGON       0  19600 
#> 2 roi_000000003 regions stroma POLYGON       0   5018.
```

Finally, an **`annot_session`** wraps a queue of images with a manifest,
a cursor, and shared label and layer templates, so a project can be
materialised, annotated, and saved for each image in turn.

``` r

sess <- at_example_session(3)
at_session_status(sess)[, c("idx", "name", "status")]
#> # A tibble: 3 × 3
#>     idx name     status 
#>   <int> <chr>    <chr>  
#> 1     1 image_01 pending
#> 2     2 image_02 pending
#> 3     3 image_03 pending
```

## Geometry validity and repair

Every constructor finalises its geometry: the CRS is cleared and, if the
result is topologically invalid,
[`sf::st_make_valid()`](https://r-spatial.github.io/sf/reference/valid.html)
is applied with a warning. ROIs you build in R are therefore valid by
construction. Geometry that arrives from elsewhere – imported GeoJSON, a
QuPath project, a hand-edited file – carries no such guarantee, so
annotatR offers an explicit audit.

[`at_check_geometry()`](https://cttir.github.io/annotatR/reference/at_check_geometry.md)
reports one row per problem across the whole project:
self-intersections, zero-area or degenerate rings, duplicate vertices,
reversed hole winding, `NA` coordinates, and vertices outside the image
bounds, each tagged by severity and by whether it can be repaired
automatically. Here we add one ROI that spills past the image edge and
one with a duplicated vertex:

``` r

proj <- at_add_roi(proj, "regions", at_roi_rect(430, 430, 620, 620, label = "tumour"))
dup  <- at_roi_polygon(
  matrix(c(0, 0, 0, 0, 40, 0, 40, 40, 0, 40), ncol = 2, byrow = TRUE),
  label = "stroma"
)
proj <- at_add_roi(proj, "regions", dup)
at_check_geometry(proj)
#> # A tibble: 2 × 4
#>   roi_id        issue              severity fixable
#>   <chr>         <chr>              <chr>    <lgl>  
#> 1 roi_000000004 out_of_bounds      warning  TRUE   
#> 2 roi_000000005 duplicate_vertices warning  TRUE
```

[`at_fix_geometry()`](https://cttir.github.io/annotatR/reference/at_fix_geometry.md)
repairs what it can – here the duplicate vertices – and reports the
rest. Out-of-bounds vertices are a boundary advisory rather than a
topological fault, so they are left untouched; clip them with
[`at_clamp()`](https://cttir.github.io/annotatR/reference/at_clamp.md)
when you want the geometry confined to the image.

``` r

proj <- at_fix_geometry(proj)
#> ✔ Repaired 2 ROIs.
at_check_geometry(proj)
#> # A tibble: 0 × 4
#> # ℹ 4 variables: roi_id <chr>, issue <chr>, severity <chr>, fixable <lgl>
```

## Pyramid levels and coordinate transforms

Whole-slide and multiplex images are pyramids: the same scene stored at
several resolutions. An ROI records the level at which its coordinates
were digitised in its `level` field, so a region drawn on a
low-resolution overview is never silently misread as full-resolution
pixels. Keeping the declared level makes every coordinate unambiguous
and every transform reversible.

Two functions move coordinates between levels.
[`at_roi_rescale()`](https://cttir.github.io/annotatR/reference/at_roi_rescale.md)
assumes an exact power-of-two pyramid and needs no image: going from
level 0 to level 2 divides coordinates by four.

``` r

r0 <- at_roi_rect(0, 0, 100, 100, label = "a")
r2 <- at_roi_rescale(r0, from_level = 0, to_level = 2)
at_roi_bbox(r2)
#> [1]  0  0 25 25
```

[`at_transform()`](https://cttir.github.io/annotatR/reference/at_transform.md)
instead uses the real per-level dimensions of an image, so it is exact
for pyramids with any downsampling ratio. For the bundled multiplex
example, whose levels measure 512, 256, and 128 pixels, the two
approaches agree:

``` r

mimg <- at_example_image("multiplex")
at_dims(mimg, level = 0)
#> [1] 512 512
at_dims(mimg, level = 2)
#> [1] 128 128
at_roi_bbox(at_transform(r0, from_level = 0, to_level = 2, img = mimg))
#> [1]  0  0 25 25
```

Both transforms are exactly invertible, so coordinates can round-trip
through any level without drift.

The companion **Masks** vignette shows how these annotations are
rasterised – applying the pixel-centre rule above – into binary,
labelled, and multi-class integer masks.

## Use of LLM tools

Portions of this package were prepared with assistance from large
language model tooling for narrowly defined, non-authorial tasks:
copyediting, prose smoothing, Markdown/LaTeX formatting, scaffolding of
boilerplate files (CI configs, build scripts), code refactoring. The
tools used were Chat AI, the LLM service of KISSKI (GWDG), and a
self-hosted Mistral Small (24B, Apache-2.0) run locally via Ollama and
the ollamar R package — local inference only, with no data sent to third
parties for the self-hosted model.
