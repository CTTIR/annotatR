# Persistence schemas are independent of the package release version.
.persistence_schema <- 1L
.source_schema <- 1L
.session_out_dir <- function() tempfile('annotatR-session-')

.source_signature <- function(path) {
  if (!file.exists(path)) return(NULL)
  info <- file.info(path)
  list(size = unname(info$size), mtime = unname(as.numeric(info$mtime)))
}

# Ordered, semantic file roles make companion inputs durable and comparable.
.source_files <- function(paths) lapply(paths,function(p)
  list(path=normalizePath(p,mustWork=TRUE),signature=.source_signature(p)))
.validate_source_files <- function(files) {
  if (is.null(files)) return(invisible(NULL))
  if (!is.list(files) || !length(files) || is.null(names(files)) || anyNA(names(files)) ||
      any(!nzchar(names(files))) || anyDuplicated(names(files))) stop('Invalid composite source files.')
  for (f in files) {
    if (!is.list(f)) stop('Invalid composite source file.')
    .check_provenance_keys(f,c('path','signature'),'source file')
    .check_string(f[['path']])
    sig<-f[['signature']]
    .check_provenance_keys(sig,c('size','mtime'),'source file signature')
    if (!is.list(sig) || !is.numeric(sig[['size']]) || length(sig[['size']])!=1L ||
        !is.finite(sig[['size']]) || sig[['size']]<0 || !is.numeric(sig[['mtime']]) ||
        length(sig[['mtime']])!=1L || !is.finite(sig[['mtime']])) stop('Invalid composite source signature.')
  }
  invisible(files)
}
.composite_unverified <- function(d) {
  backend<-d[['backend']];files<-d[['files']]
  if (identical(backend,'envi')) return(is.null(files) || !all(c('header','payload') %in% names(files)))
  if (identical(backend,'tivita')) return(is.null(files) || !'payload' %in% names(files))
  FALSE
}

.check_schema <- function(version, what) {
  if (!is.null(version) && (!is.numeric(version) || length(version) != 1L ||
      is.na(version) || version != 1)) {
    stop('Unsupported ', what, ' schema. Inspect the original file and upgrade annotatR.')
  }
}

.serializable_options <- function(x) {
  if (is.environment(x) || is.function(x) || typeof(x) %in% c('externalptr','weakref') ||
      inherits(x, 'connection')) return(FALSE)
  if (is.list(x)) return(all(vapply(x, .serializable_options, logical(1))))
  is.atomic(x) || is.null(x)
}

# Extension data never aliases a supported key. Duplicate supported keys are
# ambiguous even when exact list lookup would select the first occurrence.
.check_provenance_keys <- function(x, keys, what) {
  nms <- names(x)
  if (anyDuplicated(nms[nms %in% keys])) stop('Duplicate ', what, ' metadata keys.')
  invisible(x)
}

.check_descriptor_keys <- function(d) {
  if (!is.list(d)) return(invisible(d))
  .check_provenance_keys(d, c('schema_version','path','backend','options',
    'options_inferred','reader_contract','signature','files','options_encoding','options_identity'), 'source descriptor')
  .check_provenance_keys(d[['reader_contract']], c('axes','samples'), 'source reader contract')
  .check_provenance_keys(d[['signature']], c('size','mtime'), 'source signature')
  invisible(d)
}

.validate_descriptor <- function(d) {
  if (!is.list(d)) stop('Invalid source descriptor.')
  .check_descriptor_keys(d)
  .check_schema(d[["schema_version"]], 'source')
  .check_string(d[["path"]]); .check_string(d[["backend"]])
  if (!is.list(d[["options"]]) || !.serializable_options(d[["options"]])) stop('Invalid serializable reader options.')
  if ("options_inferred" %in% names(d)) .check_flag(d[["options_inferred"]], arg = "options_inferred")
  if (!is.null(d[["reader_contract"]])) {
    contract <- d[["reader_contract"]]
    if (!is.list(contract) || !setequal(names(contract),c('axes','samples')) ||
        length(contract)!=2L || any(!vapply(contract,function(x) is.character(x) && length(x)==1L && !is.na(x) && nzchar(x),logical(1)))) {
      stop('Invalid source reader contract.')
    }
  }
  .validate_source_files(d[['files']])
  sig <- d[["signature"]]
  if (!is.null(sig)) {
    if (!is.list(sig) || !is.numeric(sig[['size']]) || length(sig[['size']]) != 1L ||
        !is.finite(sig[['size']]) || sig[['size']] < 0 || !is.numeric(sig[['mtime']]) ||
        length(sig[['mtime']]) != 1L || !is.finite(sig[['mtime']])) stop('Invalid source signature.')
  }
  invisible(d)
}

.migrate_image <- function(img) {
  .check_image(img)
  .check_provenance_keys(img, c('source_descriptor','source','backend','meta','handle'), 'image source')
  .check_provenance_keys(img[["meta"]], 'reader_contract', 'image reader contract')
  if (length(img[["dims"]]) != 2L || anyNA(img[["dims"]]) || any(img[["dims"]] < 1L) ||
      length(img[["n_bands"]]) != 1L || is.na(img[["n_bands"]]) || img[["n_bands"]] < 1L) stop('Invalid saved image dimensions.')
  d <- img[["source_descriptor"]]
  if (!is.null(d)) {
    .validate_descriptor(d)
    d[["schema_version"]] <- .source_schema
    img[["source_descriptor"]] <- d
  } else if (is.null(img[["handle"]]) && is.character(img[["source"]]) &&
             length(img[["source"]]) == 1L && !is.na(img[["source"]]) &&
             is.character(img[["backend"]]) && length(img[["backend"]]) == 1L &&
             img[["backend"]] %in% c('raster','tiff','envi','ometiff') &&
             grepl('^(?:/|[A-Za-z]:[/\\\\]|\\\\\\\\)', img[["source"]], perl=TRUE)) {
    # Only established default readers can recover a lightweight legacy image.
    # Its original file metadata/options were not recorded; expose that fact.
    img[["source_descriptor"]] <- list(schema_version=.source_schema, path=img[["source"]],
      backend=img[["backend"]], options=list(), options_inferred=TRUE, signature=NULL)
  }
  img
}

.source_status <- function(img) {
  d <- img[["source_descriptor"]]
  if (is.null(d)) {
    return(if (!is.null(img[["handle"]])) 'in_memory' else 'unresolved')
  }
  .validate_descriptor(d)
  if (!file.exists(d[["path"]])) return('missing')
  if (!is.null(d[["signature"]]) && !identical(d[["signature"]], .source_signature(d[["path"]]))) return('changed')
  for (f in d[['files']]) {
    if (!file.exists(f[['path']])) return('missing')
    if (!identical(f[['signature']],.source_signature(f[['path']]))) return('changed')
  }
  'available'
}

#' Inspect an image source without changing annotations or reading pixels
#'
#' @param x An image or project.
#' @return A list with source status, path, backend, reader options and whether
#'   legacy options were inferred. Status is available, missing, changed,
#'   in_memory or unresolved. Size and modification time detect many source
#'   replacements, but are not a content checksum. Windowed descriptors also
#'   validate every declared companion input, including ENVI headers/payloads.
#' @export
at_inspect_source <- function(x) {
  img <- if (inherits(x,'annot_project')) x$image else x
  img <- .migrate_image(img)
  d <- img[["source_descriptor"]]
  list(status=.source_status(img), path=d[["path"]] %||% img[["source"]],
       backend=d[["backend"]] %||% img[["backend"]], options=d[["options"]],
       options_inferred=isTRUE(d[["options_inferred"]]))
}

.reopen_image <- function(img, require_pixels=FALSE) {
  img <- .migrate_image(img)
  # Actual retained arrays are immutable snapshots, including historical handles.
  if (.memory_snapshot(img)) return(img)
  status <- .source_status(img)
  if (status == 'available' && .composite_unverified(img[['source_descriptor']])) {
    status <- 'unresolved'
    img[['meta']][['source_error']] <- 'Composite source provenance is unverified; use at_relink_source() to revalidate.'
  }
  if (status == 'available' && is.null(img[["handle"]])) {
    d <- img[["source_descriptor"]]
    result <- tryCatch(do.call(at_read_image,c(list(path=d[["path"]],backend=d[["backend"]]),d[["options"]])),error=identity)
    if (!inherits(result,'error') && (!identical(result[["dims"]],img[["dims"]]) ||
        !identical(result[["n_bands"]],img[["n_bands"]]) || !identical(result[["level_dims"]],img[["level_dims"]]))) {
      result <- simpleError('Reopened source dimensions differ from saved image.')
    }
    if (!inherits(result,'error')) {
      fields <- c('backend','dtype','band_names','wavelengths','wavelength_unit','pixel_size','pixel_unit')
      changed <- fields[!vapply(fields,function(k) identical(result[[k]],img[[k]]),logical(1))]
      if (length(changed) || !identical(result[["meta"]][["reader_contract"]],img[["meta"]][["reader_contract"]]) ||
          !identical(result[["source_descriptor"]][["reader_contract"]],d[["reader_contract"]])) {
        result <- simpleError('Reopened reader metadata/decoding contract differs or is legacy-ambiguous; explicitly revalidate with at_relink_source(). Annotations are preserved.')
      }
    }
    if (inherits(result,'error')) {
      img[["meta"]][["source_error"]] <- conditionMessage(result)
      status <- 'unresolved'
    } else {
      if (is.null(d[["signature"]])) d[["signature"]] <- result[["source_descriptor"]][["signature"]]
      img[["source_descriptor"]] <- d
      img[["handle"]] <- result[["handle"]]
      img[["read_generation"]] <- result[["read_generation"]]
      img[["cache_identity"]] <- result[["cache_identity"]]
      img[["meta"]][["source_error"]] <- NULL
    }
  }
  if (!status %in% c('available','in_memory')) {
    img[["handle"]] <- NULL
    if (require_pixels) stop('Image source is ',status,': ',img[["source"]],
      '. Use at_inspect_source() and at_relink_source() with the original source and reader options. ',
      img[["meta"]][["source_error"]] %||% '')
  }
  img
}

#' Explicitly relink or revalidate an image source
#'
#' @param x An image or project. Annotations and geometry are preserved.
#' @param path Replacement source path (may be the same path to revalidate).
#' @param backend Reader backend; defaults to the saved backend.
#' @param options Reader options; defaults to the saved options.
#' @return The updated image or project. Dimensions, pyramid levels, band count
#'   and wavelengths must agree. Relinking explicitly accepts the new source
#'   and refreshes image metadata from the selected reader.
#' @export
at_relink_source <- function(x, path, backend=NULL, options=NULL) {
  project <- inherits(x,'annot_project')
  img <- if (project) x$image else x
  .check_image(img)
  .check_provenance_keys(img, c('source_descriptor','source','backend','meta','handle'), 'image source')
  d <- img[["source_descriptor"]]
  .check_descriptor_keys(d)
  fresh <- do.call(at_read_image,c(list(path=path,backend=backend %||% d[["backend"]] %||% img[["backend"]]),
                                  options %||% d[["options"]] %||% list()))
  if (!identical(fresh[["dims"]],img[["dims"]]) || !identical(fresh[["n_bands"]],img[["n_bands"]]) ||
      !identical(fresh[["level_dims"]],img[["level_dims"]]) || !identical(fresh[["wavelengths"]],img[["wavelengths"]])) {
    stop('Replacement image dimensions, pyramid levels, bands or wavelengths differ; annotations were not changed.')
  }
  # The reader owns the handle layout and all image metadata. Adopt them
  # together so tile dispatch, bands, units and backend metadata stay coherent.
  if (project) { x$image <- fresh; x } else fresh
}

.validate_project_structure <- function(p) {
  .check_project(p)
  # This validates image/source schemas without opening the external source.
  .migrate_image(p$image)
  .check_schema(p$provenance$schema_version,'project')
  rev <- p$meta$annotation_revision
  if (!is.null(rev) && (!is.numeric(rev) || length(rev)!=1L || is.na(rev) || !is.finite(rev) || rev<0 || rev!=floor(rev))) stop('Invalid saved annotation revision.')
  if (!is.list(p$layers) || (length(p$layers) &&
      (is.null(names(p$layers)) || anyDuplicated(names(p$layers))))) stop('Invalid saved layers.')
  for (layer in p$layers) {
    .check_layer(layer)
    if (!is.list(layer$rois)) stop('Invalid saved ROIs.')
    for (roi in layer$rois) {
      .check_roi(roi); .check_string(roi$id)
      if (!inherits(roi$geometry,'sfc')) stop('Invalid saved ROI geometry.')
    }
  }
  if (anyDuplicated(.all_roi_ids(p))) stop('Ambiguous duplicate ROI identifiers; inspect the original file before repair.')
  invisible(p)
}

.prepare_project <- function(p) {
  .validate_project_structure(p)
  p$image <- .migrate_image(p$image)
  if (!is.null(p$image[["source_descriptor"]]) &&
      !(.memory_snapshot(p$image) && is.list(p$image[["meta"]]) &&
        (is.null(p$image[["meta"]][["capabilities"]]) || .composite_unverified(p$image[["source_descriptor"]])))) p$image$handle <- NULL
  p$provenance$schema_version <- .persistence_schema
  p$provenance$saved_with <- .pkg_version()
  p
}

.restore_project <- function(p, materialize = TRUE) {
  .validate_project_structure(p)
  # Persisted opaque runtime identities are never reused by a new load.
  p$image$cache_identity <- .new_identity_id('image')
  p$image$read_generation <- NULL
  if (!is.null(p$image[["source_descriptor"]]) &&
      !(.memory_snapshot(p$image) && is.list(p$image[["meta"]]) &&
        (is.null(p$image[["meta"]][["capabilities"]]) || .composite_unverified(p$image[["source_descriptor"]])))) p$image$handle <- NULL
  p$image <- if (materialize) .reopen_image(p$image) else .migrate_image(p$image)
  p$provenance$schema_version <- .persistence_schema
  p
}

.migrate_session <- function(s) {
  .check_session(s); .check_schema(s$meta$schema_version,'session')
  m <- s$manifest
  required <- c('idx','path','name','status','project_path','n_rois','modified')
  if (!is.data.frame(m) || !all(required %in% names(m)) || !nrow(m) ||
      !is.numeric(m$idx) || !identical(as.numeric(m$idx),as.numeric(seq_len(nrow(m)))) ||
      !is.character(m$path) || anyNA(m$path) || any(!nzchar(m$path)) ||
      !is.character(m$project_path) || !is.character(m$name) ||
      !is.numeric(m$n_rois) || anyNA(m$n_rois) || any(m$n_rois<0) ||
      any(m$n_rois!=floor(m$n_rois)) ||
      !is.list(s$projects) || length(s$projects) != nrow(m) ||
      length(s$cursor) != 1L || !is.numeric(s$cursor) || is.na(s$cursor) ||
      s$cursor != floor(s$cursor) || s$cursor < 1L || s$cursor > nrow(m) ||
      anyNA(m$status) || any(!m$status %in% .session_statuses)) stop('Invalid saved session structure; inspect the original file.')
  if (is.null(s$meta$schema_version) && !any(c('entry_id','export_stem') %in% names(m))) {
    # Row position is the unambiguous identity of an old queue, even for repeats.
    m$entry_id <- vapply(seq_len(nrow(m)),function(i) .new_identity_id('entry'),character(1))
    m$export_stem <- m$entry_id
  }
  .validate_manifest_identity(m)
  s$manifest <- m
  for (i in seq_len(nrow(m))) if (!is.null(s$projects[[i]])) {
    p <- s$projects[[i]]
    .validate_project_structure(p)
    if (!is.null(p$meta$entry_id) && !identical(p$meta$entry_id,m$entry_id[i])) stop('Project identity does not match manifest entry.')
    p$meta$entry_id <- m$entry_id[i]
    s$projects[[i]] <- p
  }
  s$meta$schema_version <- .persistence_schema
  s
}

# Same-filesystem staging; callers may inject I/O primitives for failure tests.
# Unix rename replaces atomically. Windows uses a recoverable prior-file backup.
.atomic_save_rds <- function(object, path, overwrite=FALSE, platform=.Platform$OS.type,
                             writer=saveRDS, rename=file.rename) {
  .check_string(path); .check_flag(overwrite)
  if (file.exists(path) && !overwrite) stop(path,' already exists. Pass overwrite = TRUE to replace it.')
  dir <- dirname(path)
  if (!dir.exists(dir) && !dir.create(dir,recursive=TRUE,showWarnings=FALSE)) stop('Cannot create output directory: ',dir)
  stage <- tempfile('.stage-',tmpdir=dir)
  on.exit(unlink(stage),add=TRUE)
  writer(object,stage)
  # Detect incomplete/invalid serialization before any existing file is touched.
  readRDS(stage)
  if (file.exists(path) && !overwrite) stop(path,' already exists.')
  backup <- NULL
  if (platform == 'windows' && file.exists(path)) {
    backup <- tempfile('.previous-',tmpdir=dir)
    if (!isTRUE(rename(path,backup))) stop('Cannot back up checkpoint for replacement: ',path)
  }
  ok <- tryCatch(isTRUE(rename(stage,path)),error=function(e) FALSE)
  if (!ok) {
    if (!is.null(backup)) {
      restored <- tryCatch(isTRUE(rename(backup,path)),error=function(e) FALSE)
      if (!restored) stop('Cannot replace checkpoint. Previous valid checkpoint retained at: ',backup)
    }
    stop('Cannot replace checkpoint: ',path)
  }
  if (!is.null(backup)) unlink(backup)
  invisible(path)
}

.prepare_session <- function(s) {
  s <- .migrate_session(s)
  s$projects <- lapply(s$projects,function(p) if (is.null(p)) NULL else .prepare_project(p))
  s$meta$annotatR_version <- .pkg_version()
  s
}

.save_checkpoint <- function(candidate,cursor,write=.atomic_save_rds) {
  candidate <- .migrate_session(candidate)
  # Every project in this snapshot gets an immutable generation path. This also
  # captures unsaved edits left on other queue entries when autosave was off.
  generation <- .new_identity_id('checkpoint')
  created <- character(); published <- FALSE
  on.exit(if (!published) unlink(created),add=TRUE)
  for (i in seq_along(candidate$projects)) {
    p <- candidate$projects[[i]]
    previous <- candidate$manifest$project_path[i]
    if (is.null(p) && !is.na(previous) && nzchar(previous)) {
      p <- at_load_project(previous)
      if (!is.null(p$meta$entry_id) && !identical(p$meta$entry_id,candidate$manifest$entry_id[i])) stop("Project identity does not match manifest entry.")
      p$meta$entry_id <- candidate$manifest$entry_id[i]
      candidate$projects[[i]] <- p
    }
    if (is.null(p)) next
    path <- file.path(candidate$out_dir,'projects',paste0(candidate$manifest$export_stem[i],'-',generation,'.rds'))
    write(.prepare_project(p),path,overwrite=FALSE)
    created <- c(created,path)
    candidate$manifest$project_path[i] <- path
  }
  persisted <- .prepare_session(candidate)
  # All manifest references are complete before the only mutable file publishes.
  write(persisted,file.path(candidate$out_dir,'_session.rds'),overwrite=TRUE)
  published <- TRUE
  candidate
}

#' Inspect a saved checkpoint without modifying it
#'
#' @param path A saved project or session RDS file.
#' @return A list with valid, class, issues, and source diagnostics. Invalid or
#'   ambiguous structures are reported without guessing repairs or reading pixels.
#' @export
at_inspect_saved <- function(path) {
  .check_file(path)
  obj <- tryCatch(readRDS(path),error=identity)
  if (inherits(obj,'error')) return(list(valid=FALSE,class=NULL,issues=conditionMessage(obj),sources=list()))
  result <- tryCatch({
    if (inherits(obj,'annot_session')) {
      .migrate_session(obj)
    } else if (inherits(obj,'annot_project')) {
      .validate_project_structure(obj)
    } else stop('Not an annotatR project or session.')
    NULL
  },error=function(e) conditionMessage(e))
  projects <- if (inherits(obj,'annot_session')) obj$projects else list(obj)
  sources <- lapply(projects,function(p) {
    if (is.null(p)) return(NULL)
    tryCatch(at_inspect_source(p),error=function(e) list(status='unresolved',issue=conditionMessage(e)))
  })
  list(valid=is.null(result),class=class(obj)[1],issues=result %||% character(),sources=sources)
}
