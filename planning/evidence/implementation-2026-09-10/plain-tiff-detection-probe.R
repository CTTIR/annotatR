pkgload::load_all('/data/GitHub/CTTIR/public/annotatR-roadmap/.superpowers/sdd/ROADMAP/snapshots/T06', quiet=TRUE)
registry <- annotatR:::.backend_registry
backend <- registry[['tiff']]
backend$available_fn <- function() FALSE
registry[['tiff']] <- backend
img <- at_read_image('/tmp/annotatr-roadmap-reference/reference-rgb.tif')
tile <- at_tile(img)
jsonlite::write_json(list(backend=img$backend,dtype=img$dtype,dims=dim(tile),expected_first_row=111:115,actual_first_row=as.numeric(tile[1,,1])), '/data/GitHub/CTTIR/public/annotatR-roadmap/planning/evidence/implementation-2026-09-10/plain-tiff-detection-baseline.json',pretty=TRUE,auto_unbox=TRUE)
