# Mask agreement metrics: compare two integer label masks (an annotatR mask
# against a ground-truth .npy, or two annotators) with per-class Dice / IoU and
# an overall accuracy and Cohen's kappa. Masks are aligned by class *value*, so
# both must share a label codebook -- supply matching `values` to at_mask(), or
# remap first, since raw at_mask() ids are assignment-order dependent.

# Coerce an annot_mask or a plain matrix/array to an integer matrix.
.as_mask_matrix <- function(x, arg, call) {
  if (inherits(x, "annot_mask")) {
    m <- as.matrix(x)
  } else if (is.matrix(x) || is.array(x)) {
    m <- as.matrix(x)
  } else {
    cli::cli_abort("{.arg {arg}} must be an {.cls annot_mask} or a matrix.", call = call)
  }
  storage.mode(m) <- "integer"
  m
}

#' Agreement between two masks
#'
#' Per-class Dice and Jaccard (IoU) plus an overall accuracy and Cohen's kappa,
#' comparing a reference mask `a` against a second mask `b` (e.g. an annotatR
#' mask against a `.npy` ground truth, or two annotators). Classes are matched by
#' integer value, so both masks must use the same class codebook.
#'
#' @param a Reference `annot_mask` or integer matrix.
#' @param b Comparison `annot_mask` or integer matrix, same dimensions as `a`.
#' @param background Integer value treated as unlabeled/background and excluded
#'   from the per-class rows (still counted for overall accuracy/kappa).
#'   Default `0`.
#' @param labels Optional named vector or legend tibble (`value`, `label`)
#'   overriding the reference legend for class labels.
#' @param call The calling environment, for error reporting.
#'
#' @return A [tibble::tibble] with one row per class: `value`, `label`,
#'   `n_true`, `n_pred`, `tp`, `fp`, `fn`, `dice`, `iou`. The `overall`
#'   attribute is a list of `accuracy`, `kappa`, `mean_dice`, `mean_iou`, and
#'   `n_px`.
#' @family masks
#' @seealso [at_mask()], [at_read_npy()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' m <- at_mask(at_example_project(), "multiclass")
#' ag <- at_mask_agreement(m, m)
#' attr(ag, "overall")$kappa
at_mask_agreement <- function(a, b, background = 0L, labels = NULL,
                              call = rlang::caller_env()) {
  ma <- .as_mask_matrix(a, "a", call)
  mb <- .as_mask_matrix(b, "b", call)
  if (!identical(dim(ma), dim(mb))) {
    cli::cli_abort(
      c("{.arg a} and {.arg b} must have the same dimensions.",
        "x" = "a is {nrow(ma)}x{ncol(ma)}; b is {nrow(mb)}x{ncol(mb)}."),
      call = call
    )
  }
  background <- as.integer(background)

  # Label lookup: explicit `labels`, else the reference mask's legend, else the
  # class value as a string.
  lut <- NULL
  if (!is.null(labels)) {
    lut <- if (is.data.frame(labels)) {
      stats::setNames(as.character(labels$label), as.character(labels$value))
    } else {
      stats::setNames(as.character(labels), names(labels))
    }
  } else if (inherits(a, "annot_mask")) {
    lg <- attr(a, "legend")
    if (!is.null(lg) && nrow(lg) > 0L) {
      lut <- stats::setNames(as.character(lg$label), as.character(lg$value))
    }
  }
  label_of <- function(v) {
    key <- as.character(v)
    if (!is.null(lut) && key %in% names(lut)) unname(lut[[key]]) else key
  }

  classes <- sort(unique(c(ma[ma != background], mb[mb != background])))
  rows <- lapply(classes, function(v) {
    ta <- ma == v
    tb <- mb == v
    tp <- sum(ta & tb)
    fp <- sum(!ta & tb)
    fn <- sum(ta & !tb)
    denom_d <- 2L * tp + fp + fn
    denom_i <- tp + fp + fn
    tibble::tibble(
      value = as.integer(v), label = label_of(v),
      n_true = as.integer(sum(ta)), n_pred = as.integer(sum(tb)),
      tp = as.integer(tp), fp = as.integer(fp), fn = as.integer(fn),
      dice = if (denom_d == 0L) NA_real_ else 2 * tp / denom_d,
      iou = if (denom_i == 0L) NA_real_ else tp / denom_i
    )
  })
  tab <- if (length(rows)) do.call(rbind, rows) else tibble::tibble(
    value = integer(0), label = character(0), n_true = integer(0),
    n_pred = integer(0), tp = integer(0), fp = integer(0), fn = integer(0),
    dice = double(0), iou = double(0)
  )

  n <- length(ma)
  po <- sum(ma == mb) / n
  cats <- sort(unique(c(ma, mb)))
  pe <- sum(vapply(cats, function(c) (sum(ma == c) / n) * (sum(mb == c) / n), double(1)))
  kappa <- if (isTRUE(all.equal(pe, 1))) 1 else (po - pe) / (1 - pe)
  attr(tab, "overall") <- list(
    accuracy = po, kappa = kappa,
    mean_dice = if (nrow(tab)) mean(tab$dice, na.rm = TRUE) else NA_real_,
    mean_iou = if (nrow(tab)) mean(tab$iou, na.rm = TRUE) else NA_real_,
    n_px = as.integer(n)
  )
  tab
}
