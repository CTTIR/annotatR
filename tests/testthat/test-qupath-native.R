qp_fixture <- function() jsonlite::read_json(test_path('fixtures/qupath-native/native-array.geojson'),simplifyVector=FALSE)
qp_read <- function(x) {p <- tempfile(fileext='.geojson'); on.exit(unlink(p));jsonlite::write_json(x,p,auto_unbox=TRUE,null='null');at_read_qupath(p)}
test_that('native QuPath arrays, Features and collections recover IDs, colours and geometry', {
  native <- at_read_qupath(test_path("fixtures/qupath-native/native-array.geojson"))
  expect_identical(native$rois[[1]]$id,"level-roi")
  fs <- qp_fixture()
  for (obj in list(fs,list(type='FeatureCollection',features=fs),fs[[1]])) {
    L <- qp_read(obj)
    expect_identical(L$rois[[1]]$id,'level-roi')
    expect_identical(unname(L$style$colour['region']),'#123456')
    expect_true(L$rois[[1]]$attributes$locked)
    expect_equal(as.numeric(sf::st_bbox(L$rois[[1]]$geometry)),c(8,6,20,14))
    expect_equal(as.numeric(sf::st_area(L$rois[[1]]$geometry)),96)
    expect_identical(L$rois[[1]]$attributes$qupath_object_type,'annotation')
  }
  L <- qp_read(fs)
  expect_equal(as.numeric(sf::st_area(L$rois[[2]]$geometry)),84)
  expect_identical(unname(L$style$colour['donut']),'#ABCDEF')
  f <- fs[[1]]; f$properties <- list(objectType='detection')
  expect_identical(qp_read(f)$rois[[1]]$id,f$id)
  expect_identical(qp_read(f)$rois[[1]]$attributes$qupath_object_type,'detection')
})

test_that('malformed QuPath roots, fields and ambiguous mappings reject explicitly', {
  for(x in list(list(foo=1),list(type='FeatureCollection'),list(1),list(type='Feature',geometry=NULL))) expect_error(qp_read(x),'QuPath|GeoJSON')
  base <- qp_fixture()[[1]]
  for(value in list(1,list('a','b'),list(x='a'),'')) {
    f <- base;f$properties <- list(metadata=list(annotatR_roi_id=value))
    expect_error(qp_read(f),'metadata|mapping')
  }
  f <- base; f$properties <- list(metadata=list(annotatR_roi_id='a'),metadata=list(annotatR_roi_id='b'))
  raw <- jsonlite::toJSON(f,auto_unbox=TRUE)
  raw <- gsub('metadata.1','metadata',raw,fixed=TRUE)
  path <- tempfile();writeLines(raw,path);on.exit(unlink(path))
  expect_error(at_read_qupath(path),'[Cc]onflict|[Aa]mbiguous')
  f <- base; f$properties <- list(coordinate_schema='other',metadata=list(annotatR_coordinate_schema='annotatR-pixel-level-v1'))
  expect_error(qp_read(f),'[Cc]onflict|[Aa]mbiguous')
  f <- base;f$properties <- list(objectType='detection',object_type='annotation')
  expect_error(qp_read(f),'[Cc]onflict|[Aa]mbiguous')
  for(cls in list(list(name=list('a','b')),list(name='a',color=list(1,2,999)),list(name='a',colorRGB='red'))) {
    f <- base; f$properties <- list(classification=cls)
    expect_error(qp_read(f),'classification|colour|color')
  }
})

test_that('outbound QuPath UUID metadata preserves stable internal IDs and object kind', {
  p <- demo_project(); f <- tempfile(); on.exit(unlink(f));at_write_qupath(p,f)
  fs <- jsonlite::read_json(f)$features
  expect_true(all(vapply(fs,function(x) grepl('^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$',x$id),logical(1))))
  expect_identical(vapply(at_read_qupath(f)$rois,`[[`,character(1),'id'),unname(at_rois(p)$roi_id))
  expect_true(all(vapply(fs,function(x) !is.null(x$properties$objectType),logical(1))))
})

test_that('ambiguous IDs and malformed contracts cannot be silently repaired', {
  f <- qp_fixture()[[1]]
  expect_error(qp_read(list(f,f)),'[Dd]uplicate.*ID|[Aa]mbiguous')
  f$properties <- list(coordinate_schema=list('a','b'))
  expect_error(qp_read(f),'coordinate schema')
  p <- tempfile();on.exit(unlink(p));writeLines('{}',p)
  expect_error(at_read_qupath(p),'QuPath')
  f <- qp_fixture()[[1]];f$id <- 3
  expect_error(qp_read(f),'ID')
})

test_that('coordinate metadata consistency is exact, not tolerant numeric equality', {
  f <- qp_fixture()[[1]]
  f$properties <- list(level=100000000,metadata=list(annotatR_coordinate_level='100000001'))
  expect_error(qp_read(f),'Conflicting QuPath coordinate level')
})

for (case in c('legacy-only','current-only','consistent-both','conflicting-both')) {
  test_that(paste('QuPath classification fields use exact keys:',case), {
    f <- qp_fixture()[[1]]
    cls <- switch(case,
      'legacy-only'=list(name='legacy',colorRGB=-15584170L),
      'current-only'=list(name='legacy',color=list(18L,52L,86L)),
      'consistent-both'=list(name='legacy',color=list(18L,52L,86L),colorRGB=-15584170L),
      'conflicting-both'=list(name='legacy',color=list(18L,52L,86L),colorRGB=-1L))
    f$properties <- list(object_type='annotation',classification=cls)
    if(case=='conflicting-both') expect_error(qp_read(f),'Conflicting QuPath classification colour') else {
      L <- qp_read(f)
      expect_identical(L$rois[[1]]$label,'legacy')
      expect_identical(unname(L$style$colour['legacy']),'#123456')
      expect_identical(L$rois[[1]]$id,'00000000-0000-0000-0000-000000000101')
    }
  })
}

test_that('unsupported metadata prefixes cannot replace native UUIDs or coordinate declarations', {
  f <- qp_fixture()[[1]]
  f$properties <- list(metadata=list(annotatR_roi_id_extra='unexpected-original',
    annotatR_coordinate_schema_extra='annotatR-pixel-level-v1',annotatR_coordinate_level_extra='2'))
  r <- qp_read(f)$rois[[1]]
  expect_identical(r$id,'00000000-0000-0000-0000-000000000101')
  expect_identical(r$level,0L)
  f$properties <- list(level=2L,metadata=list(annotatR_coordinate_schema_extra='annotatR-pixel-level-v1'))
  expect_error(qp_read(f),'Ambiguous legacy coordinate level')
})

test_that('unsupported property and classification prefixes are ignored', {
  f <- qp_fixture()[[1]]
  f$properties <- list(objectType_extra='detection',object_type_extra='detection',
    level_extra=2L,coordinate_schema_extra='annotatR-pixel-level-v1',isLocked_extra=TRUE,
    classification_extra=list(name='wrong'),metadata_extra=list(annotatR_roi_id='wrong'))
  r <- qp_read(f)$rois[[1]]
  expect_identical(r$id,'00000000-0000-0000-0000-000000000101')
  expect_identical(r$level,0L)
  expect_identical(r$label,'unclassified')
  expect_false(isTRUE(r$attributes$locked))
  expect_identical(r$attributes$qupath_object_type,'annotation')
  for(key in c('name_extra','color_extra','colorRGB_extra')) {
    f$properties <- list(classification=setNames(list(if(key=='name_extra') 'wrong' else -1L),key))
    L <- qp_read(f)
    expect_identical(L$rois[[1]]$label,'unclassified')
    expect_null(.qupath_colour(f$properties$classification))
  }
})

test_that('near-prefix keys cannot satisfy required GeoJSON structure', {
  f <- qp_fixture()[[1]]
  for(key in c('type','geometry')) {
    bad <- f;names(bad)[names(bad)==key] <- paste0(key,'_extra')
    expect_error(qp_read(bad),'Malformed QuPath')
  }
  for(key in c('type','coordinates')) {
    bad <- f;names(bad$geometry)[names(bad$geometry)==key] <- paste0(key,'_extra')
    expect_error(qp_read(bad),'Malformed QuPath')
  }
  expect_error(qp_read(list(type='FeatureCollection',features_extra=list(f))),'Malformed QuPath')
  f$properties <- list();f$id_extra <- 'unsupported-feature-id';f$id <- NULL
  expect_false(identical(qp_read(f)$rois[[1]]$id,'unsupported-feature-id'))
})
