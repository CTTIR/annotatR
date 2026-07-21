# The batch annotation app

![annotatR logo](../reference/figures/logo.png)

Annotating one image is a job for
[`at_project()`](https://cttir.github.io/annotatR/reference/at_project.md)
and the ROI constructors. Annotating a *queue* of images — a plate of
serial sections, a batch of slides, a folder of cubes — is what
[`at_annotate()`](https://cttir.github.io/annotatR/reference/at_annotate.md)
is for. It wraps a Shiny and OpenSeadragon canvas around a resumable
**session**, so you can work through many images without losing your
place, your labels, or your unsaved edits.

## Building a session

A session is a queue of image paths plus a shared annotation template.
Build one explicitly with
[`at_session()`](https://cttir.github.io/annotatR/reference/at_session.md),
or grab a ready-made one for experimentation with
[`at_example_session()`](https://cttir.github.io/annotatR/reference/at_example_session.md),
which copies the bundled tissue image into a temporary directory so the
queue has real files to iterate.

``` r

sess <- at_example_session(3)
sess
#> <annot_session>
#> images: 3  |  complete: 0  |  cursor: 1
#> out_dir: /tmp/Rtmp0ZKz0b/annotatR-example-session-2d623246da00  |  autosave: TRUE
```

Every image starts with status `"pending"`, the cursor sits on the first
image, and per-image projects are materialised lazily — nothing is read
from disk until you visit it.

## Layer templates and label vocabularies

Two things are shared across the whole queue. The **label vocabulary**
is the flat list of allowed labels, bound to the number keys `1`–`9`.
The **layer template** is a list of
[`at_layer()`](https://cttir.github.io/annotatR/reference/at_layer.md)
objects — with styles from
[`at_style()`](https://cttir.github.io/annotatR/reference/at_style.md) —
stamped onto every image the first time you open it, so each slide
starts with the same empty layers ready to receive ROIs.

``` r

regions <- at_layer("regions", labels = c("tumour", "necrosis", "stroma"),
                    style = at_style(colour = "#E64B35", fill_alpha = 0.3))
lesions <- at_layer("lesions", labels = c("focus", "margin"),
                    style = at_style(colour = "#4DBBD5", z = 2))

paths <- at_session_status(sess)$path
templated <- at_session(paths,
                        labels = c("tumour", "necrosis", "stroma", "focus", "margin"),
                        layers = list(regions, lesions),
                        out_dir = tempdir())

at_layers(at_current(templated))
#> # A tibble: 2 × 6
#>   name    n_rois labels    visible locked     z
#>   <chr>    <int> <list>    <lgl>   <lgl>  <int>
#> 1 regions      0 <chr [3]> TRUE    FALSE      1
#> 2 lesions      0 <chr [2]> TRUE    FALSE      2
```

## Launching the app

With a session in hand, launch the application. This opens a browser and
blocks, so it is never run inside a vignette:

``` r

at_annotate(templated)
```

[`at_annotate()`](https://cttir.github.io/annotatR/reference/at_annotate.md)
is forgiving about its first argument: pass a session, a project, an
image, a vector of paths, a directory, or `NULL` to open the bundled
example.

## Keyboard shortcuts

The canvas is built for speed, so almost everything has a key. Draw with
the tool keys, assign a label with a digit, then commit.

| Key | Action |
|----|----|
| `n` / `p` | Next / previous image |
| `N` | Jump to next pending image |
| `1`–`9` | Assign label from the vocabulary |
| `q` | Rectangle tool |
| `w` | Polygon tool |
| `e` | Ellipse / circle tool |
| `r` | Freehand tool |
| `t` | Point tool |
| `y` | Pan / move tool |
| `d` | Delete selected ROI |
| `Ctrl`+`Z` / `Ctrl`+`Shift`+`Z` | Undo / redo |
| `Space` | Toggle mask overlay |
| `Enter` | Commit the current ROI |
| `Shift`+`Enter` | Commit and advance to next image |
| `Shift`+`V` | Copy annotations forward from previous image |
| `f` | Flag image for review |
| `s` | Save session |
| `Ctrl`+`E` | Export |
| `?` | Show help |

## Copy-forward for serial sections

Adjacent serial sections often share most of their anatomy. Rather than
redraw it, press `Shift`+`V` to copy every ROI from the previous image
onto the current one, then nudge the vertices to fit. Combined with
`Shift`+`Enter` (commit and advance), a run of near-identical sections
can be annotated in a few keystrokes each.

## Autosave and recovery

By default a session autosaves to `_session.rds` in its `out_dir` on
every commit, so a crashed browser or a closed laptop costs you nothing.
Save on demand with
[`at_save_session()`](https://cttir.github.io/annotatR/reference/at_save_session.md)
(bound to `s`), and pick up exactly where you left off with
[`at_resume()`](https://cttir.github.io/annotatR/reference/at_resume.md).

``` r

sess <- at_set_status(sess, 1, "complete")
sess <- at_next(sess)

at_save_session(sess)
recovered <- at_resume(file.path(sess$out_dir, "_session.rds"))
recovered
#> <annot_session>
#> images: 3  |  complete: 1  |  cursor: 2
#> out_dir: /tmp/Rtmp0ZKz0b/annotatR-example-session-2d623246da00  |  autosave: TRUE
```

The cursor, statuses, materialised projects, and templates all come back
intact.

## The session API without the app

Everything the canvas does to a session is available as plain functions,
which is what makes batches scriptable and testable. Inspect the queue
with
[`at_session_status()`](https://cttir.github.io/annotatR/reference/at_session_status.md),
walk it with
[`at_next()`](https://cttir.github.io/annotatR/reference/at_next.md) /
[`at_prev()`](https://cttir.github.io/annotatR/reference/at_prev.md) /
[`at_goto()`](https://cttir.github.io/annotatR/reference/at_goto.md),
and read a richer progress report — one column per label — with
[`at_manifest()`](https://cttir.github.io/annotatR/reference/at_manifest.md).

``` r

at_session_status(sess)
#> # A tibble: 3 × 7
#>     idx path                name  status project_path n_rois modified
#>   <int> <chr>               <chr> <chr>  <chr>         <int> <dttm>  
#> 1     1 /tmp/Rtmp0ZKz0b/an… imag… compl… NA                0 NA      
#> 2     2 /tmp/Rtmp0ZKz0b/an… imag… pendi… NA                0 NA      
#> 3     3 /tmp/Rtmp0ZKz0b/an… imag… pendi… NA                0 NA

at_manifest(sess)
#> # A tibble: 3 × 9
#>     idx name     path              status n_layers n_rois tumour necrosis stroma
#>   <int> <chr>    <chr>             <chr>     <int>  <int>  <int>    <int>  <int>
#> 1     1 image_01 /tmp/Rtmp0ZKz0b/… compl…        0      0      0        0      0
#> 2     2 image_02 /tmp/Rtmp0ZKz0b/… pendi…        0      0      0        0      0
#> 3     3 image_03 /tmp/Rtmp0ZKz0b/… pendi…        0      0      0        0      0
```

Use these to seed a session programmatically, pre-fill statuses, or
audit progress in a report — no Shiny required.

## Export scoping

Exports (`Ctrl`+`E`) are scoped deliberately. You choose the **layers**
to include, the **format** (GeoJSON, QuPath, or a rasterised TIFF mask),
and the **breadth** — the current image only, every completed image, or
the whole queue. Flagged and skipped images are excluded from batch
exports unless you opt them back in, so a “export all complete” pass
yields exactly the reviewed annotations and nothing half-finished.

Those export formats — and how annotatR round-trips with QuPath,
GeoJSON, and mask TIFFs — are the subject of the next vignette,
“Interoperability”.

## Use of LLM tools

Portions of this package were prepared with assistance from large
language model tooling for narrowly defined, non-authorial tasks:
copyediting, prose smoothing, Markdown/LaTeX formatting, scaffolding of
boilerplate files (CI configs, build scripts), code refactoring. The
tools used were Chat AI, the LLM service of KISSKI (GWDG), and a
self-hosted Mistral Small (24B, Apache-2.0) run locally via Ollama and
the ollamar R package — local inference only, with no data sent to third
parties for the self-hosted model.
