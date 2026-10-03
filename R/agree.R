# Quantitative agreement uses the shared validated mask metadata and exact
# durable source comparison, independently from display-label overrides.
.as_mask_matrix <- function(x, arg, call) {
  m <- if (inherits(x, "annot_mask")) as.matrix(x) else x
  if (!is.matrix(m) || length(dim(m)) != 2L || any(dim(m) < 1L))
    cli::cli_abort("{.arg {arg}} must have two positive matrix dimensions.", call = call)
  matrix(.mask_integers(m, paste0(arg, " mask values")), nrow(m), ncol(m))
}

.agreement_identity <- function(info, encoding) {
  lg <- info[["legend"]]
  key <- if (encoding == "instance") lg[["roi_id"]] else lg[["label"]]
  if (anyNA(key) || any(!nzchar(key)) || anyDuplicated(key))
    cli::cli_abort("Agreement requires unique nonmissing semantic labels or stable instance ROI IDs.")
  stats::setNames(key, as.character(lg[["value"]]))
}

# Strict mappings may have classes absent from one declared codebook, provided
# neither a shared code nor a shared identity changes its meaning.
.agreement_codebook <- function(a, b, encoding, policy) {
  ka <- .agreement_identity(a, encoding); kb <- .agreement_identity(b, encoding)
  if (policy == "by-label" && encoding == "instance")
    cli::cli_abort("Instance agreement requires stable ROI IDs, not by-label alignment.")
  if (policy == "by-id" && encoding != "instance")
    cli::cli_abort("by-id alignment is only defined for instance encodings.")
  if (policy == "strict") {
    shared_codes <- intersect(names(ka), names(kb))
    shared_keys <- intersect(unname(ka), unname(kb))
    if (!identical(unname(ka[shared_codes]), unname(kb[shared_codes])) ||
        !identical(names(ka)[match(shared_keys,ka)], names(kb)[match(shared_keys,kb)]))
      cli::cli_abort("Mask semantic codebooks conflict; explicit code_alignment is required.")
    return(b[["m"]])
  }
  if (!setequal(unname(ka), unname(kb)))
    cli::cli_abort("Explicit codebook alignment requires matching semantic identity sets.")
  mapped <- matrix(a[["metadata"]][["background"]], nrow(b[["m"]]), ncol(b[["m"]]))
  for (code in names(kb)) {
    target <- as.integer(names(ka)[match(kb[[code]],ka)])
    member <- .mask_membership(b[["m"]], as.integer(code), encoding)
    if (encoding == "bitfield") mapped[member] <- bitwOr(mapped[member], target)
    else mapped[member] <- target
  }
  mapped
}

#' Agreement between two masks
#'
#' Per-class Dice and Jaccard (IoU) plus an overall accuracy and Cohen's kappa,
#' comparing a reference mask `a` against a second mask `b` (e.g. an annotatR
#' mask against a `.npy` ground truth, or two annotators). Versioned metadata,
#' grids, source provenance, encodings and semantic codebooks are validated.
#' Plain matrices are explicit-code legacy categorical inputs and require finite
#' representable integer values; missing values are rejected.
#'
#' Categorical/binary classes use equality; bitfields use class memberships,
#' with overall accuracy measuring exact membership-set agreement and kappa NA.
#' Instance maps use stable unique ROI IDs, never display class names. No spatial
#' instance matching is inferred. Absent classes retain rows with NA Dice/IoU;
#' background-only accuracy is 1 and kappa is NA (zero Cohen denominator).
#' Mean Dice/IoU exclude absent classes and are NA if none are defined.
#'
#' @param a Reference `annot_mask` or integer matrix.
#' @param b Comparison `annot_mask` or integer matrix, same dimensions as `a`.
#' @param background Integer value treated as unlabeled/background and excluded
#'   from the per-class rows (still counted for overall accuracy/kappa).
#'   Defaults to declared metadata background, or `0` for plain matrices.
#'   Explicit values must agree with metadata; both inputs must share background.
#' @param labels Optional named vector or legend tibble (`value`, `label`)
#'   overriding display labels only. It cannot certify semantic codebook alignment.
#' @param alignment `"check"` (default) verifies shared grid/source metadata;
#'   `"assert"` records the caller's assertion of spatial alignment. Dimensions
#'   must always agree. Identical inputs permit a self-grid comparison without
#'   source descriptors; legacy pairs retain explicit-code/grid assumptions.
#' @param code_alignment `"strict"` (default) requires compatible code mappings;
#'   `"by-label"` explicitly maps categorical/binary/bitfield codes by unique
#'   semantic labels; `"by-id"` maps instance codes by stable unique `roi_id`.
#'   Remapping requires matching identity sets in both codebooks. Mixed plain
#'   matrices and annotated inputs require `alignment="assert"` and categorical
#'   encoding; plain codes then assert the annotated codebook.
#' @param call The calling environment, for error reporting.
#'
#' @return A [tibble::tibble] with one row per class: `value`, `label`,
#'   `n_true`, `n_pred`, `tp`, `fp`, `fn`, `dice`, `iou`. The `overall`
#'   attribute is a list of `accuracy`, `kappa`, `mean_dice`, `mean_iou`, and
#'   `n_px`, `encoding`, `alignment`, `code_alignment`, `background` and
#'   `nonfinite` (always `"error"`). A `comparison` attribute retains validated
#'   input metadata and legends for interpretation.
#' @family masks
#' @seealso [at_mask()], [at_read_npy()]
#' @export
#' @examplesIf requireNamespace("magick", quietly = TRUE) || requireNamespace("tiff", quietly = TRUE)
#' m <- at_mask(at_example_project(), "multiclass")
#' ag <- at_mask_agreement(m, m)
#' attr(ag, "overall")$kappa
at_mask_agreement <- function(a, b, background = 0L, labels = NULL,
                              call = rlang::caller_env(),
                              alignment = c("check", "assert"),
                              code_alignment = c("strict", "by-label", "by-id")) {
  alignment <- .check_choice(alignment, c("check", "assert"), default = missing(alignment), call = call)
  code_alignment <- .check_choice(code_alignment, c("strict", "by-label", "by-id"), default = missing(code_alignment), call = call)
  ma <- .as_mask_matrix(a, "a", call)
  mb <- .as_mask_matrix(b, "b", call)
  if (!identical(dim(ma), dim(mb)))
    cli::cli_abort("Masks must have the same dimensions.", call = call)
  bg <- .mask_integers(background, "background")
  if (length(bg) != 1L) cli::cli_abort("background must be one integer.", call = call)
  ia <- if (inherits(a,"annot_mask")) .mask_info(a) else NULL
  ib <- if (inherits(b,"annot_mask")) .mask_info(b) else NULL
  infos <- Filter(Negate(is.null), list(ia,ib))
  if (length(infos)) {
    backgrounds <- vapply(infos, function(i) i[["metadata"]][["background"]], integer(1))
    if (missing(background)) bg <- backgrounds[1]
    if (any(backgrounds != bg)) cli::cli_abort("Mask background declarations conflict.", call = call)
  }
  encoding <- if (length(infos)) infos[[1]][["metadata"]][["encoding"]] else "categorical"
  if (length(infos) == 2L) {
    if (encoding != ib[["metadata"]][["encoding"]]) cli::cli_abort("Mask encodings differ.", call = call)
    provenance <- if (identical(a,b)) "self-grid" else .mask_alignment(ia,ib,alignment)
    mb <- .agreement_codebook(ia,ib,encoding,code_alignment)
  } else {
    if (code_alignment != "strict") cli::cli_abort("Codebook remapping requires two annotated masks.", call = call)
    if (length(infos) && (alignment != "assert" || encoding != "categorical"))
      cli::cli_abort("Mixed matrix/mask comparison requires categorical encoding and alignment = 'assert'.", call = call)
    if (length(infos) && any(!c(ma,mb) %in% c(bg,infos[[1]][["legend"]][["value"]])))
      cli::cli_abort("Matrix values are absent from the asserted mask codebook.", call = call)
    provenance <- if (alignment == "assert") "asserted" else "legacy-explicit-codes"
  }
  # Use both legends in strict mode so declared absent classes remain visible.
  lg <- if (!is.null(ia)) ia[["legend"]] else if (!is.null(ib)) ib[["legend"]] else .mask_empty_legend()
  if (!is.null(ia) && !is.null(ib) && code_alignment == "strict")
    lg <- rbind(lg,ib[["legend"]][!ib[["legend"]][["value"]] %in% lg[["value"]],])
  lut <- stats::setNames(lg[["label"]], as.character(lg[["value"]]))
  if (!is.null(labels)) {
    if (is.data.frame(labels)) {
      override <- .mask_legend_normalize(labels)
      lut <- stats::setNames(override[["label"]], as.character(override[["value"]]))
    } else {
      if (!is.character(labels) || is.null(names(labels)) || anyNA(labels) ||
          any(!nzchar(names(labels))) || anyDuplicated(names(labels)))
        cli::cli_abort("Display labels must be a named character vector or legend table.", call = call)
      lut <- labels
    }
  }
  label_of <- function(v) {
    key <- as.character(v)
    if (key %in% names(lut)) unname(lut[[key]]) else key
  }
  classes <- if (encoding == "bitfield") sort(lg[["value"]]) else
    sort(unique(c(ma[ma != bg], mb[mb != bg], lg[["value"]])))
  rows <- lapply(classes, function(v) {
    ta <- .mask_membership(ma,v,encoding); tb <- .mask_membership(mb,v,encoding)
    tp <- sum(ta & tb); fp <- sum(!ta & tb); fn <- sum(ta & !tb)
    denom_d <- 2 * tp + fp + fn; denom_i <- tp + fp + fn
    tibble::tibble(
      value = as.integer(v), label = label_of(v),
      n_true = as.integer(sum(ta)), n_pred = as.integer(sum(tb)),
      tp = as.integer(tp), fp = as.integer(fp), fn = as.integer(fn),
      dice = if (denom_d == 0) NA_real_ else 2 * tp / denom_d,
      iou = if (denom_i == 0) NA_real_ else tp / denom_i)
  })
  tab <- if (length(rows)) do.call(rbind,rows) else tibble::tibble(
    value=integer(),label=character(),n_true=integer(),n_pred=integer(),
    tp=integer(),fp=integer(),fn=integer(),dice=double(),iou=double())
  n <- length(ma); po <- sum(ma == mb) / n
  cats <- sort(unique(c(ma,mb)))
  pe <- sum(vapply(cats,function(v) (sum(ma==v)/n)*(sum(mb==v)/n),double(1)))
  kappa <- if (encoding == "bitfield" || pe == 1) NA_real_ else (po-pe)/(1-pe)
  defined_mean <- function(x) if (any(!is.na(x))) mean(x,na.rm=TRUE) else NA_real_
  attr(tab,"overall") <- list(accuracy=po,kappa=kappa,
    mean_dice=defined_mean(tab$dice),mean_iou=defined_mean(tab$iou),n_px=as.integer(n),
    encoding=encoding,alignment=provenance,code_alignment=code_alignment,
    background=bg,nonfinite="error")
  attr(tab,"comparison") <- list(reference=if (!is.null(ia)) ia[c("metadata","legend")] else NULL,
    prediction=if (!is.null(ib)) ib[c("metadata","legend")] else NULL)
  tab
}
