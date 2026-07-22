# Static content pages shown at the ends of the navbar: About + Workflow at the
# start, References + Impressum at the end. These carry no server logic -- just
# prose in a readable, width-constrained column.

.prose <- function(...) shiny::div(class = "at-prose", ...)

.page_about <- function() {
  bslib::card(
    bslib::card_header("About annotatR"),
    .prose(shiny::markdown(
      "**annotatR** is an R toolkit and Shiny application for annotating
hyperspectral image cubes -- in particular TIVITA *SpecCube* data -- in several
independent semantic layers, and exporting those annotations as label masks and
vector geometry for downstream analysis and machine learning.

It reproduces, in R, the multi-layer region-of-interest workflow used to label
tissue in hyperspectral studies. A single cube can carry several overlapping
annotations at once:

- **anatomy** -- the structural / anatomical region,
- **state** -- the physiological or injury state (e.g. burn depth),
- **uncertain** -- areas you are unsure about,
- **artefact** -- blood, instruments, drape and other non-tissue.

Because these layers overlap freely, you can capture a wound region, the
**penumbra ring** around an injury, and blood artefacts on top of tissue as
distinct annotations of the same image.

Every cube is shown as a natural-colour RGB rendered from its visible bands, and
every region maps directly onto the cube grid -- so per-region **spectra are
extracted from the original hyperspectral data**, not from the display image.

*Package:* `CTTIR/annotatR` &nbsp;&bull;&nbsp; *Maintainer:* R. Heller"
    ))
  )
}

.page_workflow <- function() {
  bslib::card(
    bslib::card_header("Workflow"),
    .prose(shiny::markdown(
      "Work left to right through the navigation bar.

### 1. Data
Load a folder of images or cubes, or start from the queue already configured for
the session. The table lists every image and its status.

### 2. Annotate
Three columns: the **queue** (left), the **canvas and tools** (middle), and
**layers & labels** (right).

- **Tools:** pan, rectangle, polygon, freehand, circle, point, edit (drag a
  region), erase (click a region to remove it).
- Pick a **layer** (anatomy / state / uncertain / artefact) -- the label list
  updates to that layer's vocabulary. Add your own layers and labels with the
  fields beneath each list.
- Draw a region and it joins the **active layer** with the **active label**.
  Overlapping regions are expected and fine.
- Annotations **autosave**. Mark an image **Complete** or **Flag** it as you go.
- Press **?** (or the *? shortcuts* button) for the full keyboard-shortcut list:
  `n`/`p` to move between images, `q w e r t y` for tools, `1`-`9` for labels,
  `Ctrl+Z` to undo, `Shift+Enter` to complete and advance.

### 3. Summary
Preview the derived **mask** (binary / labelled / multiclass, with an overlap
policy), read the **per-region spectra**, and inspect or delete individual
regions in the ROI table.

### 4. Export
Choose the **formats** (mask TIFF, GeoJSON, QuPath GeoJSON, ROI CSV) and a
**scope** (current / complete / all / flagged), then **Export & download** to get
a `.zip`. A copy is also written to the session's export folder."
    ))
  )
}

.page_references <- function() {
  bslib::card(
    bslib::card_header("References"),
    .prose(shiny::markdown(
      "### Software
- **annotatR** -- `CTTIR/annotatR`.
- R Core Team. *R: A Language and Environment for Statistical Computing.*
  R Foundation for Statistical Computing.
- Pebesma, E. (2018). *Simple Features for R: Standardized Support for Spatial
  Vector Data.* The R Journal 10(1), 439-446. (package `sf`)
- Pebesma, E. *stars: Spatiotemporal Arrays, Raster and Vector Data Cubes.* CRAN.
- Hijmans, R. J. *terra: Spatial Data Analysis.* CRAN.
- Ooms, J. *magick: Advanced Graphics and Image-Processing in R.* CRAN.
- Chang, W. et al. *shiny: Web Application Framework for R.* CRAN.
- Sievert, C. et al. *bslib: Custom Bootstrap Sass Themes for shiny and rmarkdown.* CRAN.

Each package citation can be reproduced in R with `citation(\"<package>\")`.

### Hyperspectral imaging
- TIVITA hyperspectral imaging system, Diaspective Vision GmbH -- source of the
  *SpecCube* format (500-995 nm, 5 nm steps) read by this tool.

### Study references
*Add the clinical and methodological references for your specific study here.*"
    ))
  )
}

.page_impressum <- function() {
  bslib::card(
    bslib::card_header("Impressum"),
    .prose(
      shiny::markdown(
        "*Legal notice (Impressum) -- template. Complete the bracketed fields with
your own legal details before publishing this application.*

**Information pursuant to § 5 DDG (formerly § 5 TMG):**

Responsible for content:"
      ),
      shiny::tags$blockquote(shiny::HTML(paste(
        "R. Heller", "[Institution / Affiliation]", "[Street and number]",
        "[Postcode, City]", "[Country]", sep = "<br>"))),
      shiny::markdown("**Contact:**"),
      shiny::tags$blockquote(shiny::HTML(
        "Email: <a href=\"mailto:raban.heller@outlook.com\">raban.heller@outlook.com</a>")),
      shiny::markdown(
        "Add any further legally required details as they apply to your institution
-- e.g. *represented by*, commercial-register entry, VAT identification number,
or the competent professional supervisory authority.

The bracketed placeholders above are **not** legal statements; replace them with
accurate information before this notice is used publicly."
      )
    )
  )
}
