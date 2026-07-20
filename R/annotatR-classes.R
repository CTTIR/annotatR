#' annotatR S3 classes
#'
#' @description
#' annotatR represents annotations with a small set of S3 classes. This page
#' collects them so they can be cross-referenced from the documentation.
#'
#' \describe{
#'   \item{`annot_image`}{A backend-agnostic image handle holding metadata and a
#'     lazy tile accessor. Created by `at_read_image()` or `at_example_image()`.}
#'   \item{`annot_roi`}{A single region of interest: an `sf` geometry in image
#'     pixel coordinates at a declared pyramid level. Created by the
#'     `at_roi_*()` constructors.}
#'   \item{`annot_layer`}{A named collection of ROIs sharing a label vocabulary
#'     and a visual style. Created by [at_layer()].}
#'   \item{`annot_project`}{An image plus a named set of layers and provenance.
#'     Created by [at_project()].}
#'   \item{`annot_session`}{A resumable batch-annotation session over a queue of
#'     images. Created by [at_session()].}
#'   \item{`annot_mask`}{A rasterised mask: a labelled or binary integer matrix
#'     with a legend. Created by `at_mask()`.}
#'   \item{`annot_style`}{A layer style specification. Created by [at_style()].}
#'   \item{`annot_summary`}{A compact per-label project summary. Created by
#'     [at_summary()].}
#' }
#'
#' @name annotatR-classes
#' @aliases annot_image annot_roi annot_layer annot_project annot_session
#'   annot_mask annot_style annot_summary
#' @family images
#' @seealso [at_project()], [at_layer()]
NULL
