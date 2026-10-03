quant_fixture <- function(name) test_path("fixtures", "analytical", name)
quant_project <- function() at_project(at_read_image(quant_fixture("cube.hdr")),
  at_read_geojson(quant_fixture("analysis-rois.geojson"))[[1]])
quant_mask <- function(name, codes = NULL, encoding="categorical", ids=NULL) {
  if (is.null(codes)) codes <- c(A=1L,B=2L,absent=if (encoding=="bitfield") 4L else 3L)
  m <- as.matrix(at_read_npy(quant_fixture(name)))
  lg <- tibble::tibble(value=unname(codes), label=names(codes))
  if (!is.null(ids)) lg$roi_id <- ids
  .new_annot_mask(m, lg, 0L, rev(dim(m)), "multiclass", encoding=encoding)
}

test_that("finite-only summaries match every independent oracle row", {
  p <- quant_project()
  expected <- jsonlite::read_json(quant_fixture("analysis-expected.json"))$finite_omit_statistics
  ex <- at_extract(p, stat="all", nonfinite="omit")
  for (e in expected) {
    row <- ex[ex$label == e$roi & ex$band == e$band, ]
    expect_equal(row$n_px, rep(e$n_selected, 7))
    expect_equal(row$n_valid, rep(e$n_valid, 7))
    expect_equal(row$n_invalid, rep(e$n_invalid, 7))
    for (s in c("mean","median","sd","min","max","sum"))
      expect_equal(row$value[row$stat==s], e[[s]], tolerance=1e-12)
    expect_equal(row$value[row$stat=="n"], e$n_selected)
  }
  expect_true(all(ex$unit == "nm"))
  expect_equal(at_extract_spectrum(p, nonfinite="omit")$value, ex$value[ex$stat=="mean"])
  expect_error(at_extract(p, nonfinite="error"), "nonfinite")
  expect_error(at_extract_spectrum(p, nonfinite=c("propagate","omit","error")), "one|single")
  default <- at_extract(p)
  expect_true(all(is.na(default$value[default$n_invalid > 0])))
  expect_identical(attr(ex,"analysis")$nonfinite, "omit")
  expect_identical(attr(ex,"analysis")$level, 0L)
  raw <- at_tile(p$image)
  at_plot_image(p$image, bands=1L)
  expect_identical(at_tile(p$image), raw)
  expect_true(any(!is.finite(at_extract_pixels(p)$value)))
})

test_that("empty, singleton, and wholly invalid support have explicit counts", {
  p <- quant_project()
  for (xy in list(c(0,0),c(1,0))) {
    p$layers <- list(L=at_layer_add(at_layer("L"),at_roi_point(xy[1],xy[2],label="point")))
    ex <- NULL
    expect_warning(ex <- at_extract(p, bands=1L, stat="all", nonfinite="omit"), NA)
    expect_equal(ex$n_px,rep(1L,7))
    expect_true(is.na(ex$value[ex$stat=="sd"]))
    if (xy[1]==0) {
      expect_equal(ex$n_valid,rep(0L,7))
      expect_true(all(is.na(ex$value[ex$stat!="n"])))
    }
  }
  p$layers <- list(L=at_layer_add(at_layer("L"), at_roi_point(100,100,label="outside")))
  expect_equal(nrow(at_extract(p, nonfinite="omit")),0L)
})

test_that("wavelength values retain declared units and absent units remain unknown", {
  dir <- tempfile(); dir.create(dir); withr::defer(unlink(dir,recursive=TRUE))
  file.copy(quant_fixture("cube.dat"),file.path(dir,"cube.dat"))
  hdr <- readLines(quant_fixture("cube.hdr"))
  hdr <- sub("450, 550, 650", "0.65, 0.45, 0.55", hdr, fixed=TRUE)
  for (unit in c("um",NA_character_)) {
    lines <- hdr[!grepl("wavelength units",hdr,fixed=TRUE)]
    if (!is.na(unit)) lines <- c(lines,paste("wavelength units =",unit))
    writeLines(lines,file.path(dir,"cube.hdr"))
    img <- at_read_image(file.path(dir,"cube.hdr"))
    expect_identical(at_bands(img)$unit,rep(unit,3))
    p <- quant_project(); p$image <- img
    sp <- at_extract_spectrum(p,nonfinite="omit")
    expect_equal(sp$wavelength[sp$roi_id==sp$roi_id[1]],c(0.45,0.55,0.65))
    expect_equal(sp$band[sp$roi_id==sp$roi_id[1]],c(2L,3L,1L))
    expect_identical(at_plot_spectrum(sp)$labels$x,
      if (is.na(unit)) "spectral coordinate (unit unknown)" else "spectral coordinate (um)")
  }
  sp$unit[1] <- "nm"
  expect_error(at_plot_spectrum(sp), "units")
})

test_that("physical area uses declared calibration level independent of reporting level", {
  e <- jsonlite::read_json(quant_fixture("physical-area-expected.json"),simplifyVector=TRUE)
  r <- at_read_geojson(quant_fixture("physical-roi-level1.geojson"))[[1]]$rois[[1]]
  img <- new_annot_image("area", "raster", c(10L,8L),2L,list(c(10L,8L),c(4L,2L)),1L,
    pixel_size=c(0.5,3),pixel_unit="um")
  expect_equal(at_roi_area(r,level=1L,image=img),e$geometric_area_level1_px2)
  expect_equal(at_roi_area(r,level=0L,image=img),e$geometric_area_level0_px2)
  for (lev in 0:1) expect_equal(at_roi_area(r,level=lev,units="physical",image=img),e$physical_area_um2)
  r$attributes$pixel_size <- c(0.5,3)
  expect_error(at_roi_area(r,level=1L,units="physical"),"calibration|ambiguous")
  r$attributes$pixel_size_level <- 0L
  r$attributes$pixel_unit <- "um"
  expect_error(at_roi_area(r,level=1L,units="physical"),"image|Image")
  img$pixel_size <- c(NA,NA); img$pixel_unit <- "unknown"
  r$attributes <- list()
  expect_error(at_roi_area(r,level=1L,units="physical",image=img),"calibration|pixel_size")
})

test_that("categorical comparison requires semantic alignment and reproduces exact oracle", {
  a <- quant_mask("categorical-reference.npy")
  b <- quant_mask("categorical-prediction.npy")
  remap <- quant_mask("categorical-prediction-remapped.npy",c(A=2L,B=1L,absent=3L))
  expect_error(at_mask_agreement(a,b),"provenance|alignment")
  ag <- at_mask_agreement(a,b,alignment="assert")
  expect_equal(ag$dice,c(.75,.75,NA))
  expect_equal(ag$iou,c(.6,.6,NA))
  expect_equal(attr(ag,"overall")$accuracy,3/4)
  expect_equal(attr(ag,"overall")$kappa,5/8)
  expect_error(at_mask_agreement(a,remap,alignment="assert"),"codebook")
  expect_error(at_mask_agreement(a,remap,alignment="assert",labels=c(A="A",B="B")),"codebook")
  aligned <- at_mask_agreement(a,remap,alignment="assert",code_alignment="by-label")
  expect_equal(aligned$dice,ag$dice)
  expect_equal(attr(aligned,"overall")$accuracy,3/4)
  expect_equal(attr(aligned,"overall")$kappa,5/8)
  bg <- matrix(0L,2,2)
  expect_true(is.na(attr(at_mask_agreement(bg,bg),"overall")$kappa))
})

test_that("bitfield agreement compares memberships and withholds categorical kappa", {
  a <- quant_mask("bitfield-reference.npy",encoding="bitfield")
  b <- quant_mask("bitfield-prediction.npy",encoding="bitfield")
  ag <- at_mask_agreement(a,b,alignment="assert")
  expect_equal(ag$dice,c(1,3/5,NA))
  expect_equal(ag$iou,c(1,3/7,NA))
  expect_equal(attr(ag,"overall")$accuracy,2/3)
  expect_true(is.na(attr(ag,"overall")$kappa))
  expect_identical(attr(ag,"overall")$encoding,"bitfield")
  expect_error(at_mask_agreement(a,quant_mask("categorical-reference.npy"),alignment="assert"),"encoding")
})

test_that("instance comparisons use stable IDs, never repeated class labels", {
  codes <- c(cell=1L,cell=2L,cell=4L)
  a <- quant_mask("categorical-reference.npy",codes,"instance",c("roi-a","roi-b","roi-c"))
  b <- quant_mask("categorical-prediction-remapped.npy",codes,"instance",c("roi-b","roi-a","roi-c"))
  expect_error(at_mask_agreement(a,b,alignment="assert"),"codebook|ID")
  expect_error(at_mask_agreement(a,b,alignment="assert",code_alignment="by-label"),"instance|ID")
  ag <- at_mask_agreement(a,b,alignment="assert",code_alignment="by-id")
  expect_equal(ag$dice,c(.75,.75,NA))
  expect_equal(attr(ag,"overall")$accuracy,.75)
  missing <- quant_mask("categorical-reference.npy",codes,"instance")
  expect_error(at_mask_agreement(missing,missing),"ID")
})

test_that("agreement validates plain values and backgrounds before integer coercion", {
  good <- matrix(0L,2,2)
  for (v in list(.5,NA_real_,NaN,Inf,-Inf,2147483648)) {
    bad <- good; bad[1] <- v
    expect_error(at_mask_agreement(good,bad),"integer|finite")
  }
  for (bg in list(.5,NA_real_,Inf,c(0,1),numeric()))
    expect_error(at_mask_agreement(good,good,background=bg),"integer|background")
  expect_error(at_mask_agreement(array(1L,c(2,2,2)),good),"matrix|dimensions")
})


test_that("per-band wavelength units and calibration declaration keys are exact", {
  p <- quant_project()
  p$image$wavelength_unit <- c("nm","um","nm")
  expect_identical(at_bands(p$image)$unit,c("nm","um","nm"))
  ex <- at_extract(p,nonfinite="omit")
  expect_identical(ex$unit[1:3],c("nm","um","nm"))
  expect_error(at_plot_spectrum(ex),"units")
})

test_that("calibration declaration keys are exact and units are physical", {
  r <- at_roi_rect(0,0,10,10,label="A",pixel_size_extra=c(2,3))
  expect_error(at_roi_area(r,units="physical"),"pixel_size")
  expect_identical(r$attributes$pixel_size_extra,c(2,3))
  r$attributes <- list(pixel_size=c(2,3),pixel_unit="px")
  expect_error(at_roi_area(r,units="physical"),"unit|calibration")
  r$attributes <- list(pixel_size=c(2,3),pixel_size=c(3,4))
  expect_error(at_roi_area(r,units="physical"),"Duplicate|duplicate")
})

test_that("raw finite boundary values survive extraction and display contrast", {
  for (endian in c("little","big")) {
    img <- at_read_image(test_path("fixtures","readers","binary",paste0("int32-",endian,".hdr")))
    before <- at_tile(img)
    p <- at_project(img,at_layer_add(at_layer("L"),at_roi_rect(0,0,4,1,label="all")))
    ex <- at_extract(p,stat="all",nonfinite="error")
    expect_equal(ex$value[ex$stat=="min"],-2147483648)
    expect_equal(ex$n_valid,rep(4L,7))
    expect_equal(ex$n_invalid,rep(0L,7))
    at_plot_image(img,rgb=c(1L,1L,1L))
    expect_identical(at_tile(img),before)
    expect_identical(at_extract(p,stat="all",nonfinite="error"),ex)
  }
})

test_that("agreement carries exact shared grid/source validation through sidecars", {
  a <- quant_mask("categorical-reference.npy")
  b <- quant_mask("categorical-prediction.npy")
  descriptor <- list(schema_version=1L,path="/synthetic/analysis.ome.tif",backend="ometiff",
    options=list(channel=matrix(1L,1,1)),signature=list(size=100,mtime=10),
    reader_contract=list(axes="yxb",samples="raw-scalar-v1"))
  for (nm in c("a","b")) {
    m <- get(nm)
    attr(m,"mask_metadata")$source <- list(descriptor=descriptor,entry_id=nm)
    assign(nm,m)
  }
  expect_identical(attr(at_mask_agreement(a,b),"overall")$alignment,"verified")
  changed <- b
  attr(changed,"mask_metadata")$source$descriptor$options$channel <- 1L
  expect_error(at_mask_agreement(a,changed),"source|options|conflict")
  expect_identical(attr(at_mask_agreement(a,changed,alignment="assert"),"overall")$alignment,"asserted")
  changed <- b
  attr(changed,"mask_metadata")$grid$origin <- c(1,0)
  expect_error(at_mask_agreement(a,changed),"grid|alignment")
  changed <- b
  attr(changed,"mask_metadata")$source$descriptor$reader_contract <- NULL
  attr(changed,"mask_metadata")$source$descriptor$reader_contract_extra <- descriptor$reader_contract
  expect_error(at_mask_agreement(a,changed),"contract|unverified")
  path <- tempfile(fileext=".npy"); withr::defer(unlink(c(path,paste0(path,".legend.json"))))
  at_write_npy(changed,path)
  expect_error(at_mask_agreement(a,at_read_npy(path)),"contract|unverified")
  at_write_npy(b,path,overwrite=TRUE)
  expect_identical(attr(at_mask_agreement(a,at_read_npy(path)),"overall")$alignment,"verified")
})

test_that("binary, nonzero background and absent-only outcomes are explicit", {
  a <- .new_annot_mask(matrix(c(0L,1L,1L,0L),2,2),
    tibble::tibble(value=1L,label="foreground"),0L,c(2L,2L),"binary",encoding="binary")
  b <- a; b[2] <- 0L
  ag <- at_mask_agreement(a,b,alignment="assert")
  expect_equal(ag$dice,2/3)
  expect_equal(ag$iou,1/2)
  expect_equal(attr(ag,"overall")$accuracy,3/4)
  expect_identical(attr(ag,"overall")$encoding,"binary")
  expect_error(at_mask_agreement(a,b,background=1L,alignment="assert"),"background")
  empty <- a; empty[] <- 0L
  ag <- at_mask_agreement(empty,empty)
  expect_true(is.na(ag$dice) && is.na(ag$iou))
  expect_true(is.na(attr(ag,"overall")$mean_dice))
  expect_true(is.na(attr(ag,"overall")$mean_iou))
  expect_true(is.na(attr(ag,"overall")$kappa))
  other <- .new_annot_mask(matrix(c(9L,1L,1L,9L),2,2),
    tibble::tibble(value=1L,label="foreground"),0L,c(2L,2L),"multiclass",encoding="categorical",background=9L)
  expect_identical(attr(at_mask_agreement(other,other),"overall")$background,9L)
  expect_equal(at_mask_agreement(as.matrix(other),as.matrix(other),background=9L)$dice,1)
  expect_error(at_mask_agreement(other,other,background=0L),"background")
})

test_that("explicit bit remapping preserves membership sets and instances retain their IDs", {
  a <- quant_mask("bitfield-reference.npy",encoding="bitfield")
  b <- quant_mask("bitfield-prediction.npy",encoding="bitfield")
  remapped <- matrix(c(0L,2L,2L,1L,3L,3L,0L,0L,0L,1L,1L,2L),3,4,byrow=TRUE)
  c <- .new_annot_mask(remapped,tibble::tibble(value=c(2L,1L,4L),label=c("A","B","absent")),
    0L,c(4L,3L),"multiclass",encoding="bitfield")
  ag <- at_mask_agreement(a,c,alignment="assert",code_alignment="by-label")
  expect_equal(ag$dice,c(1,3/5,NA))
  expect_equal(ag$iou,c(1,3/7,NA))
  expect_equal(attr(ag,"overall")$accuracy,2/3)
  expect_identical(attr(ag,"comparison")$prediction$metadata$codebook$value,c(2L,1L,4L))
  expect_error(at_mask_agreement(a,b,alignment=c("check","assert")),"single|one")
  expect_error(at_mask_agreement(a,b,code_alignment=c("strict","by-label","by-id")),"single|one")
})

test_that("new nonzero-level calibration needs an explicit physical unit", {
  r <- at_roi_rect(0,0,2,1,label="A",level=1L,pixel_size=c(2,3),pixel_size_level=1L)
  expect_error(at_roi_area(r,level=1L,units="physical"),"unit")
  r$attributes$pixel_unit_extra <- "um"
  expect_error(at_roi_area(r,level=1L,units="physical"),"unit")
  r$attributes$pixel_unit <- "um"
  expect_equal(at_roi_area(r,level=1L,units="physical"),12)
})

test_that("legacy guessed ENVI units do not silently authorize reopened pixels", {
  dir <- tempfile(); dir.create(dir); withr::defer(unlink(dir,recursive=TRUE))
  file.copy(quant_fixture("cube.dat"),file.path(dir,"cube.dat"))
  hdr <- readLines(quant_fixture("cube.hdr"))
  writeLines(hdr[!grepl("wavelength units",hdr,fixed=TRUE)],file.path(dir,"cube.hdr"))
  img <- at_read_image(file.path(dir,"cube.hdr"))
  expect_true(all(is.na(at_bands(img)$unit)))
  img$wavelength_unit <- "nm"; img$handle <- NULL
  reopened <- .reopen_image(img)
  expect_null(reopened$handle)
  expect_match(reopened$meta$source_error,"metadata|ambiguous")
  expect_error(at_tile(reopened),"unresolved|relink|available")
})


test_that("agreement counts and ratios match every independent oracle class", {
  expected <- jsonlite::read_json(quant_fixture("agreement-expected.json"))
  for (encoding in c("categorical","bitfield")) {
    a <- quant_mask(paste0(encoding,"-reference.npy"),encoding=encoding)
    b <- quant_mask(paste0(encoding,"-prediction.npy"),encoding=encoding)
    ag <- at_mask_agreement(a,b,alignment="assert")
    for (e in expected[[encoding]]$per_class) {
      row <- ag[ag$value==e$value,]
      for (nm in c("value","label","n_true","n_pred","tp","fp","fn"))
        expect_identical(row[[nm]],e[[nm]])
      for (nm in c("dice","iou")) expect_equal(row[[nm]],e[[nm]]$value %||% NA_real_,tolerance=1e-12)
    }
    expect_identical(attr(ag,"overall")$n_px,12L)
  }
})
