# Control hub: the single source of truth for a controlled annotation session.
# It holds the session, a monotonic state revision, a bounded event ring
# buffer, request and idempotency records, and the view/selection/staging
# state an attached app mirrors. Tokens are never stored in the hub or the
# handle: they live in a package-private registry keyed by instance id, so a
# serialised handle cannot carry them.

.control_registry <- new.env(parent = emptyenv())
.control_tokens <- new.env(parent = emptyenv())

.new_control_hub <- function(session, root, ttl_seconds, host, port, read_only,
                             max_body_bytes) {
  hub <- new.env(parent = emptyenv())
  hub$instance_id <- paste0("instance-", .uuid())
  hub$session_id <- paste0("session-", .uuid())
  hub$protocol <- .contract$control
  hub$protocol_version <- .contract$version
  hub$created <- Sys.time()
  hub$expires_at <- hub$created + ttl_seconds
  hub$ttl_seconds <- ttl_seconds
  hub$pid <- Sys.getpid()
  hub$host <- host
  hub$port <- as.integer(port)
  hub$root <- root
  hub$read_only <- isTRUE(read_only)
  hub$max_body_bytes <- as.integer(max_body_bytes)
  hub$session <- session
  hub$revision <- 0L
  hub$event_seq <- 0L
  hub$events <- list()
  hub$requests <- new.env(parent = emptyenv())
  hub$request_order <- character()
  hub$idempotency <- new.env(parent = emptyenv())
  hub$view <- list(level = 0L, bounds = NULL, band_group = NULL, tool = "pan",
                   overlay = list(show = FALSE, mask_type = "labelled", alpha = 0.5))
  hub$selection <- character()
  hub$staged <- NULL
  hub$last_commit <- NULL
  hub$annotation_status <- "clean"
  hub$status <- "running"
  hub$last_origin <- "control"
  hub$apps <- new.env(parent = emptyenv())
  hub$image_ids <- new.env(parent = emptyenv())
  hub$server <- NULL
  hub$manifest_path <- NA_character_
  class(hub) <- c("at_control_hub", class(hub))
  hub
}

# Current project, materialised lazily and kept in the hub session.
.hub_project <- function(hub) {
  i <- hub$session$cursor
  p <- hub$session$projects[[i]]
  if (is.null(p)) {
    p <- .materialize_project(hub$session, i)
    hub$session$projects[[i]] <- p
  }
  p
}

# Content-derived image id for a queue entry, cached by path, size and mtime.
.hub_image_id <- function(hub, i) {
  path <- hub$session$manifest$path[i]
  info <- file.info(path)
  key <- paste(path, info$size, as.numeric(info$mtime), sep = "|")
  hit <- hub$image_ids[[key]]
  if (!is.null(hit)) {
    return(hit)
  }
  p <- hub$session$projects[[i]]
  id <- if (!is.null(p)) {
    .image_id(p$image, .source_files(p$image))
  } else if (!is.na(info$size)) {
    paste0("sha256:", substr(.digest_json(list(files = list(.sha256_file(path)))), 1L, 16L))
  } else {
    NA_character_
  }
  assign(key, id, envir = hub$image_ids)
  id
}

# Record a state change: bump the revision and append an event.
.hub_bump <- function(hub, type, payload = list(), origin = list(kind = "control")) {
  hub$revision <- hub$revision + 1L
  hub$last_origin <- origin$kind
  .hub_event(hub, type, payload, origin)
}

# Append an event without changing the revision (e.g. a completed export).
.hub_event <- function(hub, type, payload = list(), origin = list(kind = "control")) {
  hub$event_seq <- hub$event_seq + 1L
  ev <- list(
    event_id = paste0(hub$instance_id, ":", hub$event_seq),
    seq = hub$event_seq,
    type = type,
    session_id = hub$session_id,
    state_revision = as.character(hub$revision),
    time = .utc_stamp(),
    origin = origin,
    payload = if (length(payload)) payload else .json_object()
  )
  hub$events <- c(hub$events, list(ev))
  cap <- .interop_limits()$control_max_events_buffer
  if (length(hub$events) > cap) {
    hub$events <- utils::tail(hub$events, cap)
  }
  invisible(ev)
}

.hub_event_cursor <- function(hub) {
  if (hub$event_seq == 0L) {
    return(paste0(hub$instance_id, ":0"))
  }
  paste0(hub$instance_id, ":", hub$event_seq)
}

# Events after a cursor. A cursor from another instance, or one older than the
# retained buffer, forces a full resync.
.hub_events_after <- function(hub, after = NULL, limit = 100L) {
  limit <- max(1L, min(as.integer(limit), .interop_limits()$control_max_events_page))
  events <- hub$events
  oldest <- if (length(events)) events[[1]]$seq else hub$event_seq + 1L
  resync <- FALSE
  from_seq <- oldest - 1L
  if (!is.null(after) && nzchar(after)) {
    inst <- sub(":[^:]*$", "", after)
    seq <- suppressWarnings(as.integer(sub("^.*:", "", after)))
    if (!identical(inst, hub$instance_id) || is.na(seq) || seq > hub$event_seq) {
      resync <- TRUE
    } else if (seq < oldest - 1L) {
      resync <- TRUE
    } else {
      from_seq <- seq
    }
  }
  sel <- Filter(function(e) e$seq > from_seq, events)
  more <- length(sel) > limit
  sel <- utils::head(sel, limit)
  next_cursor <- if (length(sel)) sel[[length(sel)]]$event_id else {
    if (!resync && !is.null(after) && nzchar(after)) after else .hub_event_cursor(hub)
  }
  list(events = sel, next_cursor = next_cursor, resync_required = resync,
       has_more = more, state_revision = as.character(hub$revision))
}

.roi_summary <- function(project, limit = 2000L) {
  rois <- list()
  for (nm in names(project$layers)) {
    for (r in project$layers[[nm]]$rois) {
      if (length(rois) >= limit) break
      bb <- as.numeric(sf::st_bbox(r$geometry))
      rois[[length(rois) + 1L]] <- list(
        roi_id = r$id, layer = nm, label = r$label, level = r$level,
        geom_type = as.character(sf::st_geometry_type(r$geometry)),
        bbox = list(xmin = bb[1], ymin = bb[2], xmax = bb[3], ymax = bb[4]),
        source = r$source, locked = isTRUE(r$attributes$locked),
        review_status = r$attributes$review_status %||% "unreviewed"
      )
    }
  }
  rois
}

# The explicit state snapshot returned by GET /v1/state.
.hub_state <- function(hub) {
  s <- hub$session
  m <- s$manifest
  proj <- tryCatch(.hub_project(hub), error = function(e) NULL)
  img <- if (is.null(proj)) NULL else proj$image
  n_total <- if (is.null(proj)) 0L else sum(vapply(proj$layers, function(L) length(L$rois), integer(1)))
  limit <- 2000L
  list(
    protocol = hub$protocol,
    protocol_version = hub$protocol_version,
    instance_id = hub$instance_id,
    session_id = hub$session_id,
    state_revision = as.character(hub$revision),
    event_cursor = .hub_event_cursor(hub),
    status = hub$status,
    mode = if (hub$read_only) "read_only" else "annotate",
    annotation_status = if (hub$read_only) "read_only" else hub$annotation_status,
    expires_at = .utc_stamp(hub$expires_at),
    coordinate_convention = .coordinate_convention(),
    queue = lapply(seq_len(nrow(m)), function(i) {
      list(entry_id = sprintf("entry-%04d", i), queue_index = i, name = m$name[i],
           status = m$status[i], n_rois = as.integer(m$n_rois[i]),
           image_id = .hub_image_id(hub, i))
    }),
    current = if (is.null(proj)) NULL else list(
      entry_id = sprintf("entry-%04d", s$cursor),
      queue_index = as.integer(s$cursor),
      annotation_revision = at_annotation_revision(proj),
      image = list(
        image_id = .hub_image_id(hub, s$cursor),
        source_name = basename(img$source),
        width = img$level_dims[[1]][1], height = img$level_dims[[1]][2],
        n_levels = img$n_levels, n_bands = img$n_bands,
        image_kind = .image_kind(img),
        value_unit = at_hsi_meta(img)$value_unit,
        calibration_status = at_hsi_meta(img)$calibration$status %||% "missing",
        wavelength_unit = img$wavelength_unit %||% NA_character_
      ),
      layers = unname(lapply(proj$layers, .layer_record)),
      rois = .roi_summary(proj, limit),
      rois_truncated = n_total > limit,
      mask_types = list("binary", "labelled", "multiclass")
    ),
    view = hub$view,
    selection = as.list(hub$selection),
    staged = if (is.null(hub$staged)) NULL else list(
      patch_id = hub$staged$patch_id, summary = hub$staged$summary,
      base_revision = hub$staged$base_revision, proposed_revision = hub$staged$proposed_revision
    ),
    last_commit = hub$last_commit,
    apps = list(connected = length(ls(hub$apps)))
  )
}

.hub_handshake <- function(hub) {
  caps <- at_interop_capabilities(target = c("app", "control"))
  list(
    protocol = hub$protocol,
    protocol_version = hub$protocol_version,
    annotatr_version = .pkg_version(),
    r_version = as.character(getRversion()),
    shiny_version = .pkg_version_or_na("shiny"),
    session_id = hub$session_id,
    instance_id = hub$instance_id,
    state_revision = as.character(hub$revision),
    capability_digest = caps$digest,
    capabilities = list(
      view = TRUE, selection = TRUE, annotation_stage = !hub$read_only,
      annotation_commit = !hub$read_only, mask_preview = TRUE, export = TRUE,
      training_export = TRUE, session_load = TRUE, session_save = !hub$read_only
    ),
    status = caps$control$status,
    coordinate_convention = .coordinate_convention(),
    geometry_formats = list("qupath_geojson", "geojson"),
    mask_formats = list("mask_tiff", "mask_npy"),
    event_cursor = .hub_event_cursor(hub),
    expires_at = .utc_stamp(hub$expires_at)
  )
}

.hub_health <- function(hub) {
  caps <- at_interop_capabilities(target = "control")
  list(
    protocol = hub$protocol,
    protocol_version = hub$protocol_version,
    annotatr_version = .pkg_version(),
    instance_id = hub$instance_id,
    status = hub$status,
    capability_digest = caps$digest,
    uptime_seconds = round(as.numeric(difftime(Sys.time(), hub$created, units = "secs")), 3),
    expires_at = .utc_stamp(hub$expires_at)
  )
}

# Store a request record, keeping the registry bounded.
.hub_record_request <- function(hub, record) {
  id <- record$request_id
  if (!exists(id, envir = hub$requests, inherits = FALSE)) {
    hub$request_order <- c(hub$request_order, id)
  }
  assign(id, record, envir = hub$requests)
  cap <- 1000L
  if (length(hub$request_order) > cap) {
    drop <- hub$request_order[seq_len(length(hub$request_order) - cap)]
    rm(list = drop, envir = hub$requests)
    hub$request_order <- utils::tail(hub$request_order, cap)
  }
  invisible(record)
}
