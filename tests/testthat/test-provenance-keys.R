# Prefix members are extension data; only the exact supported key is authority.
provenance_key_mask <- function(entry = 'entry-a', backend = 'ometiff') {
  m <- .mask_recover(matrix(c(1L, 0L, 0L, 1L), 2, 2))
  attr(m, 'mask_metadata')$status <- 'declared'
  attr(m, 'mask_metadata')$source <- list(entry_id = entry, descriptor = list(
    schema_version = 1L, path = '/synthetic/square.ome.tif', backend = backend,
    options = list(), signature = list(size = 100, mtime = 10),
    reader_contract = list(axes = 'yxb', samples = 'raw-scalar-v1')))
  m
}
provenance_key_rename <- function(x, key) {
  names(x)[names(x) == key] <- paste0(key, '_extra')
  x
}
provenance_key_roundtrip <- function(m, dir) {
  p <- tempfile(tmpdir = dir, fileext = '.npy')
  at_write_npy(m, p)
  at_read_npy(p)
}

test_that('a prefix reader contract cannot verify square OME masks', {
  a <- provenance_key_mask()
  b <- provenance_key_mask('entry-b')
  attr(b, 'mask_metadata')$source$descriptor <- provenance_key_rename(
    attr(b, 'mask_metadata')$source$descriptor, 'reader_contract')
  dir <- withr::local_tempdir()
  for (candidate in list(b, provenance_key_roundtrip(b, dir))) {
    d <- attr(candidate, 'mask_metadata')$source$descriptor
    expect_null(d[['reader_contract']])
    expect_identical(d[['reader_contract_extra']], list(axes = 'yxb', samples = 'raw-scalar-v1'))
    expect_error(at_mask_derive(a, candidate, keep_label = '1'), 'reader contract.*unverified')
    asserted <- at_mask_derive(a, candidate, keep_label = '1', alignment = 'assert')
    expect_identical(attr(asserted, 'mask_metadata')$derivation$anatomy_alignment, 'asserted')
    expect_identical(as.matrix(asserted), matrix(c(1L, 0L, 0L, 1L), 2, 2))
  }
})

test_that('required descriptor, contract and signature names cannot be supplied by prefixes', {
  m <- provenance_key_mask()
  descriptor <- attr(m, 'mask_metadata')$source$descriptor
  for (key in c('path', 'backend', 'options')) {
    d <- provenance_key_rename(descriptor, key)
    expect_error(.validate_descriptor(d), 'path|backend|options|reader|character|string')
  }
  for (key in c('axes', 'samples')) {
    d <- descriptor; d$reader_contract <- provenance_key_rename(d$reader_contract, key)
    expect_error(.validate_descriptor(d), 'reader contract')
  }
  for (key in c('size', 'mtime')) {
    bad <- m
    attr(bad, 'mask_metadata')$source$descriptor$signature <- provenance_key_rename(descriptor$signature, key)
    expect_error(.mask_info(bad), 'signature')
  }
  for (key in c('schema_version', 'grid', 'codebook')) {
    bad <- m; attr(bad, 'mask_metadata') <- provenance_key_rename(attr(bad, 'mask_metadata'), key)
    expect_error(.mask_info(bad), 'schema')
  }
  for (key in c('dims', 'level', 'origin', 'stride')) {
    bad <- m; attr(bad, 'mask_metadata')$grid <- provenance_key_rename(attr(bad, 'mask_metadata')$grid, key)
    expect_error(.mask_info(bad), 'grid')
  }
})

test_that('optional extension flags and metadata cannot change alignment or be rewritten', {
  dir <- withr::local_tempdir()
  a <- provenance_key_mask(backend = 'custom')
  attr(a, 'mask_metadata')$source$descriptor$reader_contract <- NULL
  for (key in c('options_inferred', 'reader_contract', 'signature', 'schema_version')) {
    b <- a; attr(b, 'mask_metadata')$source$entry_id <- 'entry-b'
    d <- attr(b, 'mask_metadata')$source$descriptor
    if (key == 'signature') { attr(a, 'mask_metadata')$source$descriptor$signature <- NULL; d$signature <- NULL }
    d[[paste0(key, '_extra')]] <- switch(key, options_inferred = TRUE,
      reader_contract = 'opaque custom contract', signature = 'opaque signature', schema_version = 99L)
    attr(b, 'mask_metadata')$source$descriptor <- d
    recovered <- tryCatch(provenance_key_roundtrip(b, dir), error = identity)
    expect_false(inherits(recovered, 'error'))
    candidates <- if (inherits(recovered, 'error')) list(b) else list(b, recovered)
    for (candidate in candidates) {
      expect_no_error(at_mask_derive(a, candidate, keep_label = '1'))
      expect_identical(attr(candidate, 'mask_metadata')$source$descriptor[[paste0(key, '_extra')]], d[[paste0(key, '_extra')]])
    }
  }
  b <- a; attr(b, 'mask_metadata')$source$entry_id <- 'entry-b'
  attr(b, 'mask_metadata')$source$options_status_extra <- 'legacy-json'
  expect_no_error(at_mask_derive(a, b, keep_label = '1'))
  for (key in c('source', 'descriptor')) {
    b <- a
    if (key == 'source') attr(b, 'mask_metadata') <- provenance_key_rename(attr(b, 'mask_metadata'), key)
    else attr(b, 'mask_metadata')$source <- provenance_key_rename(attr(b, 'mask_metadata')$source, key)
    for (candidate in list(b, provenance_key_roundtrip(b, dir))) {
      expect_error(at_mask_derive(a, candidate, keep_label = '1'), 'provenance.*insufficient')
      md <- attr(candidate, 'mask_metadata')
      expect_null(if (key == 'source') md[['source']] else md$source[['descriptor']])
      extra <- if (key == 'source') md[['source_extra']][['descriptor']] else md$source[['descriptor_extra']]
      expect_null(extra[['options_encoding']])
    }
  }
  b <- a; attr(b, 'mask_metadata')$source$entry_id <- NULL
  attr(b, 'mask_metadata')$source$entry_id_extra <- list(opaque = 'kept')
  expect_no_error(.mask_info(b))
})

test_that('sidecar recovery ignores prefix declarations but requires exact declared storage fields', {
  dir <- withr::local_tempdir(); p <- file.path(dir, 'mask.npy')
  .npy_write_matrix(matrix(c(1L, 0L, 0L, 1L), 2), p)
  write_sidecar <- function(j) jsonlite::write_json(j, paste0(p, '.legend.json'), auto_unbox = TRUE, null = 'null')
  for (j in list(list(level_extra = 7L), list(dims_extra = c(9L, 9L)),
                list(legend_extra = list(broken = 1)), list(mask_metadata_extra = list(schema_version = 99L)),
                list(storage_extra = list(shape = c(2L, 2L), axes = 'xy')))) {
    write_sidecar(j)
    got <- at_read_npy(p)
    expect_identical(attr(got, 'level'), 0L)
    expect_identical(attr(got, 'mask_metadata')$status, 'legacy-default')
    expect_identical(at_mask_legend(got)$label, '1')
  }
  for (key in c('shape', 'axes')) {
    write_sidecar(list(storage = provenance_key_rename(list(shape = c(2L, 2L), axes = 'yx'), key)))
    expect_error(at_read_npy(p), 'storage|Storage')
    expect_error(at_read_mask(p), 'storage|Storage')
  }
  at_write_npy(provenance_key_mask(), p, overwrite = TRUE)
  original <- jsonlite::read_json(paste0(p, '.legend.json'), simplifyVector = FALSE)
  for (key in c('options', 'schema_version')) {
    j <- original
    d <- j$mask_metadata$source$descriptor
    if (key == 'options') d <- provenance_key_rename(d, key)
    else d$options <- provenance_key_rename(d$options, key)
    j$mask_metadata$source$descriptor <- d; write_sidecar(j)
    expect_error(at_read_npy(p), 'reader options|option encoding')
  }
  j <- original; d <- j$mask_metadata$source$descriptor
  d <- provenance_key_rename(d, 'options_encoding'); d$options <- list(mapping = list(1L, 2L))
  j$mask_metadata$source$descriptor <- d; write_sidecar(j)
  back <- at_read_npy(p)
  expect_identical(attr(back, 'mask_metadata')$source$options_status, 'legacy-json')
  expect_identical(attr(back, 'mask_metadata')$source$descriptor$options_encoding_extra, 'typed-json-v2')
})

test_that('reopen uses exact contracts and leaves annotations available for explicit relink', {
  skip_if_not_installed('tiff')
  dir <- withr::local_tempdir(); path <- file.path(dir, 'square.tif')
  tiff::writeTIFF(matrix(c(0, 1, 1, 0), 2), path, bits.per.sample = 8L, compression = 'none')
  p <- at_project(at_read_image(path, backend = 'tiff'), at_layer('L'), entry_id = 'retained-entry')
  p <- at_add_roi(p, 'L', at_roi_rect(0, 0, 1, 1, 'retained'))
  saved <- file.path(dir, 'project.rds')
  for (location in c('source_descriptor', 'meta')) {
    bad <- p; bad$image[[location]] <- provenance_key_rename(bad$image[[location]], 'reader_contract')
    at_save_project(bad, saved, overwrite = TRUE)
    back <- at_load_project(saved)
    expect_null(back$image$handle)
    expect_identical(at_rois(back)$roi_id, at_rois(p)$roi_id)
    expect_identical(at_rois(back)$geometry, at_rois(p)$geometry)
    expect_error(at_tile(back$image), 'revalidate|relink')
    linked <- at_relink_source(back, path)
    expect_identical(at_rois(linked)$roi_id, at_rois(p)$roi_id)
    expect_identical(at_tile(linked$image), at_tile(p$image))
  }
  legacy <- p$image
  legacy$source_descriptor <- provenance_key_rename(legacy$source_descriptor, 'schema_version')
  legacy$source_descriptor$schema_version_extra <- 99L
  legacy$source_descriptor$options_inferred_extra <- TRUE
  legacy$source_descriptor <- provenance_key_rename(legacy$source_descriptor, 'signature')
  legacy$source_descriptor$signature_extra <- 'opaque'
  expect_no_error(migrated <- .migrate_image(legacy))
  expect_identical(migrated$source_descriptor[['schema_version']], 1L)
  expect_false(at_inspect_source(migrated)$options_inferred)
  expect_identical(at_inspect_source(migrated)$status, 'available')
})

test_that('duplicate authoritative provenance keys reject without selecting a value', {
  m <- provenance_key_mask()
  for (location in c('metadata', 'source', 'descriptor', 'signature', 'contract', 'grid')) {
    bad <- m; md <- attr(bad, 'mask_metadata')
    if (location == 'metadata') md <- c(md, list(schema_version = 99L))
    if (location == 'source') md$source <- c(md$source, list(descriptor = list(path = '/other')))
    if (location == 'descriptor') md$source$descriptor <- c(md$source$descriptor, list(path = '/other'))
    if (location == 'signature') md$source$descriptor$signature <- c(md$source$descriptor$signature, list(size = 999))
    if (location == 'contract') md$source$descriptor$reader_contract <- c(md$source$descriptor$reader_contract, list(axes = 'xyb'))
    if (location == 'grid') md$grid <- c(md$grid, list(level = 7L))
    attr(bad, 'mask_metadata') <- md
    expect_error(.mask_info(bad), 'duplicate|Duplicate|contract')
  }
  dir <- withr::local_tempdir(); p <- file.path(dir, 'mask.npy')
  .npy_write_matrix(matrix(c(1L, 0L, 0L, 1L), 2), p)
  # Literal JSON preserves duplicate keys that serializers may rename.
  for (json in c(
    '{"level":0,"level":7}',
    '{"storage":{"shape":[2,2],"axes":"yx","axes":"xy"}}',
    '{"mask_metadata":{"source":{"descriptor":{"path":"/one","path":"/two","backend":"custom","options":[]}}}}',
    '{"mask_metadata":{"source":{"descriptor":null,"descriptor":{"path":"/other"}}}}',
    '{"mask_metadata":{"source":null,"source":{"entry_id":"other"}}}')) {
    writeLines(json, paste0(p, '.legend.json'))
    expect_error(at_read_npy(p), 'duplicate|Duplicate')
  }
})

test_that('custom backend extension metadata does not create a reader contract', {
  dir <- withr::local_tempdir(); path <- file.path(dir, 'source.custom'); writeLines('source', path)
  backend <- 't09b-custom-provenance'
  at_backend_register(backend, read_fn = function(path, ...) {
    new_annot_image(path, backend, c(2L, 2L), 1L, list(c(2L, 2L)), 1L,
      handle = list(data = array(1:4, c(2, 2, 1))),
      meta = list(reader_contract_extra = list(axes = 'custom', samples = 'custom')))
  }, tile_fn = function(img, level, xrange, yrange, bands) img$handle$data,
  detect_fn = function(path) FALSE, available_fn = function() TRUE)
  withr::defer(rm(list = backend, envir = .backend_registry))
  img <- at_read_image(path, backend = backend)
  expect_null(img$source_descriptor[['reader_contract']])
  expect_identical(img$meta[['reader_contract_extra']], list(axes = 'custom', samples = 'custom'))
  p <- at_project(img, at_layer_add(at_layer('L'), at_roi_rect(0, 0, 1, 1, 'kept')))
  saved <- file.path(dir, 'custom.rds'); at_save_project(p, saved)
  back <- at_load_project(saved)
  expect_identical(at_tile(back$image), array(1:4, c(2, 2, 1)))
  expect_identical(at_rois(back)$roi_id, at_rois(p)$roi_id)
  for (location in c('image', 'meta')) {
    bad <- img
    if (location == 'image') bad <- c(bad, list(source_descriptor = list(path = '/other')))
    else bad$meta <- c(bad$meta, list(reader_contract = NULL, reader_contract = list(axes = 'yxb', samples = 'raw-scalar-v1')))
    class(bad) <- class(img)
    expect_error(.migrate_image(bad), 'Duplicate')
  }
})

test_that('explicit derivation records only exact source declarations', {
  a <- provenance_key_mask(); b <- provenance_key_mask('entry-b')
  attr(b, 'mask_metadata') <- provenance_key_rename(attr(b, 'mask_metadata'), 'source')
  derived <- at_mask_derive(a, b, b, keep_label = '1', alignment = 'assert')
  provenance <- attr(derived, 'mask_metadata')$derivation
  expect_null(provenance[['anatomy_source']])
  expect_null(provenance[['artefact_source']])
  expect_identical(provenance$anatomy_alignment, 'asserted')
  expect_identical(provenance$artefact_alignment, 'asserted')
})

test_that('reader option duplicate names remain exact data across the provenance boundary', {
  m <- provenance_key_mask(backend = 'custom')
  options <- structure(list(1L, 2L), names = c('schema_version', 'schema_version'))
  attr(options, 'custom') <- list(axes = 'a', axes = 'b')
  attr(m, 'mask_metadata')$source$descriptor$options <- options
  back <- provenance_key_roundtrip(m, withr::local_tempdir())
  expect_identical(attr(back, 'mask_metadata')$source$descriptor$options, options)
  expect_no_error(at_mask_derive(m, back, keep_label = '1'))
})

test_that('metadata overrides reject duplicate declarations before merging them', {
  dir <- withr::local_tempdir(); p <- file.path(dir, 'mask.npy')
  m <- provenance_key_mask(); at_write_npy(m, p)
  for (override in list(list(background = 0L, background = 9L),
      list(grid = list(level = 0L, level = 7L)),
      list(source = list(descriptor = list(path = '/one', path = '/two'))))) {
    expect_error(at_read_npy(p, metadata = override), 'Duplicate')
  }
})

test_that('relink defaults and mask source capture reject ambiguous descriptors', {
  skip_if_not_installed('tiff')
  path <- test_path('fixtures', 'readers', 'images', 'reference-uint16.tif')
  img <- at_read_image(path, backend = 'tiff')
  img$source_descriptor <- c(img$source_descriptor, list(options = list(unrecorded = TRUE)))
  expect_error(at_relink_source(img, path), 'Duplicate')
  img <- tiny_image()
  img$source_descriptor <- attr(provenance_key_mask(), 'mask_metadata')$source$descriptor
  img <- c(img, list(source_descriptor = list(path = '/other')))
  class(img) <- 'annot_image'
  expect_error(at_mask(at_roi_rect(0, 0, 1, 1, '1'), image = img), 'Duplicate')
})

test_that('legacy source migration requires exact outer image declarations', {
  skip_if_not_installed('tiff')
  path <- test_path('fixtures', 'readers', 'images', 'reference-uint16.tif')
  original <- at_read_image(path, backend = 'tiff')
  original$source_descriptor <- NULL; original$handle <- NULL
  migrated <- .migrate_image(original)
  expect_identical(migrated$source_descriptor$path, normalizePath(path))
  expect_true(migrated$source_descriptor$options_inferred)
  for (key in c('source', 'backend')) {
    bad <- provenance_key_rename(original, key)
    migrated <- .migrate_image(bad)
    expect_null(migrated[['source_descriptor']])
    expect_identical(migrated[[paste0(key, '_extra')]], original[[key]])
    inspection <- at_inspect_source(migrated)
    expect_identical(inspection$status, 'unresolved')
    expect_null(inspection[[if (key == 'source') 'path' else 'backend']])
    expect_null(.reopen_image(bad)[['handle']])
  }
})

test_that('a prefix image metadata container cannot authorize saved TIFF pixels', {
  skip_if_not_installed('tiff')
  path <- test_path('fixtures', 'readers', 'images', 'reference-uint16.tif')
  p <- at_project(at_read_image(path, backend = 'tiff'), at_layer('L'), entry_id = 'exact-entry')
  p <- at_add_roi(p, 'L', at_roi_rect(0, 0, 1, 1, 'retained'))
  bad <- p; bad$image <- provenance_key_rename(bad$image, 'meta')
  extra <- bad$image[['meta_extra']]
  saved <- file.path(withr::local_tempdir(), 'prefix-container.rds')
  at_save_project(bad, saved)
  back <- at_load_project(saved)
  expect_null(back$image[['handle']])
  expect_null(back$image[['meta']][['reader_contract']])
  expect_identical(back$image[['meta_extra']], extra)
  expect_identical(at_rois(back)$roi_id, at_rois(p)$roi_id)
  expect_identical(at_rois(back)$geometry, at_rois(p)$geometry)
  expect_identical(back$meta$entry_id, 'exact-entry')
  expect_error(at_tile(back$image), 'revalidate|relink')
  relinked <- at_relink_source(back, path)
  expect_identical(at_tile(relinked$image), at_tile(p$image))
  expect_identical(at_rois(relinked)$roi_id, at_rois(p)$roi_id)
  expect_identical(at_rois(relinked)$geometry, at_rois(p)$geometry)
})

test_that('custom reader prefix metadata containers stay extension data', {
  dir <- withr::local_tempdir(); path <- file.path(dir, 'source.custom'); writeLines('source', path)
  backend <- 't09b-prefix-container'
  at_backend_register(backend, read_fn = function(path, ...) {
    img <- new_annot_image(path, backend, c(2L, 2L), 1L, list(c(2L, 2L)), 1L,
      handle = list(data = array(1:4, c(2, 2, 1))),
      meta = list(reader_contract = list(axes = 'custom', samples = 'custom')))
    provenance_key_rename(img, 'meta')
  }, tile_fn = function(img, level, xrange, yrange, bands) img$handle$data,
  detect_fn = function(path) FALSE, available_fn = function() TRUE)
  withr::defer(rm(list = backend, envir = .backend_registry))
  img <- at_read_image(path, backend = backend)
  expect_null(img[['source_descriptor']][['reader_contract']])
  expect_null(img[['meta']])
  expect_identical(img[['meta_extra']][['reader_contract']], list(axes = 'custom', samples = 'custom'))
  saved <- file.path(dir, 'custom.rds'); at_save_project(at_project(img), saved)
  back <- at_load_project(saved)
  expect_null(back$image[['meta']][['reader_contract']])
  expect_identical(back$image[['meta_extra']], img[['meta_extra']])
  expect_identical(at_tile(back$image), array(1:4, c(2, 2, 1)))
})

test_that('outer image provenance duplicates and prefix runtime handles are not authority', {
  img <- tiny_image()
  for (key in c('source', 'backend', 'meta', 'handle')) {
    bad <- c(img, setNames(list('contradiction'), key)); class(bad) <- class(img)
    expect_error(.migrate_image(bad), 'Duplicate')
  }
  img$handle <- list(data = array(1:100, c(10, 10, 1)))
  expect_identical(at_inspect_source(img)$status, 'in_memory')
  expect_identical(.reopen_image(img)[['handle']], img[['handle']])
  bad <- provenance_key_rename(img, 'handle')
  expect_identical(at_inspect_source(bad)$status, 'unresolved')
  expect_null(.reopen_image(bad)[['handle']])
  expect_identical(.reopen_image(bad)[['handle_extra']], img[['handle']])
})

test_that('pixel reopening and dispatch require the exact outer backend', {
  skip_if_not_installed('tiff')
  path <- test_path('fixtures', 'readers', 'images', 'reference-uint16.tif')
  img <- at_read_image(path, backend = 'tiff')
  bad <- provenance_key_rename(img, 'backend')
  expect_error(at_tile(bad), 'backend|revalidate|relink|character|string')
  bad$handle <- NULL
  back <- .reopen_image(bad)
  expect_null(back[['handle']])
  expect_identical(back[['backend_extra']], 'tiff')
  expect_error(at_tile(back), 'backend|revalidate|relink|character|string')
})
