pkgload::load_all('/tmp/annotatr-roadmap-baseline-source', quiet = TRUE)
options(annotatR.author = 'fixture')
assignInNamespace('.now', function() as.POSIXct('2026-01-01 00:00:00', tz='UTC'), ns='annotatR')
out <- '/tmp/annotatr-roadmap-legacy'
path <- file.path(out, 'source.tif')
invisible(tiff::writeTIFF(matrix(c(0,1,1,0), 2, 2), path,
                          bits.per.sample = 8L, compression = 'none'))
image <- at_read_image(path)
project <- at_project(image, name = 'legacy project')
project <- at_add_layer(project, at_layer('tissue', labels = c('first', 'second')))
project <- at_add_roi(project, 'tissue', at_roi_rect(0, 0, 1, 1, 'first'))
at_save_project(project, file.path(out, 'project-full.rds'), overwrite = TRUE)
light <- project; light$image$handle <- NULL
at_save_project(light, file.path(out, 'project-lite.rds'), overwrite = TRUE)
sess <- at_session(c(path, path), labels = c('first', 'second'),
                   out_dir = file.path(out, 'checkpoint'), autosave = FALSE)
sess$projects[[1]] <- light
second <- light
second$layers[[1]]$rois[[1]]$label <- 'second'
sess$projects[[2]] <- second
sess$manifest$n_rois <- c(1L, 1L)
sess$manifest$status <- c('in_progress', 'in_progress')
at_save_session(sess, file.path(out, 'session-lite.rds'), overwrite = TRUE)
memory <- annotatR:::new_annot_image(
  source = 'memory:legacy', backend = 'envi', dims = c(3L,2L),
  n_levels = 1L, level_dims = list(c(3L,2L)), n_bands = 2L,
  wavelengths = c(500,600), wavelength_unit = 'nm', dtype = 'float64',
  handle = list(data = array(as.double(1:12), c(2,3,2))))
at_save_project(at_project(memory, name='legacy memory'),
                file.path(out, 'project-memory.rds'), overwrite = TRUE)
cat('Writer package:', as.character(packageVersion('annotatR')), '\n')
cat('Runtime baseline: f69bf201f651c845ab496f76e25638bc919d4b13\n')
cat('Original ROI:', at_rois(project)$roi_id, '\n')
cat('Original TIFF pixels:', as.vector(at_tile(image)), '\n')
cat('Legacy manifest columns:', paste(names(sess$manifest), collapse=', '), '\n')
cat('Schemas and source descriptors absent:', is.null(sess$meta$schema_version), is.null(image$source_descriptor), '\n')
