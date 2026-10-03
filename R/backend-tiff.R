# TIFF backends.
#
# "tiff"    - pyramidal / multi-directory TIFF via the base `tiff` package,
#             treating IFDs as pyramid levels when their dims decrease.
# "ometiff" - OME-TIFF, qptiff (Akoya PhenoImager), and vendor formats via
#             `RBioFormats` (Bioconductor, optional). Exposes pyramid levels and
#             channel metadata where present.

# ---- tiff backend ----------------------------------------------------------

# Coerce a readTIFF result (a single image or a list of them) into a list of
# [y, x, band] arrays, ordered by decreasing size (level 0 first).
.tiff_to_levels <- function(x) {
  imgs <- if (is.list(x)) x else list(x)
  imgs <- lapply(imgs, function(a) {
    if (length(dim(a)) == 2L) array(a, dim = c(dim(a), 1L)) else a
  })
  sizes <- vapply(imgs, function(a) dim(a)[1] * dim(a)[2], numeric(1))
  imgs <- imgs[order(sizes, decreasing = TRUE)]
  lapply(imgs, function(a) {
    storage.mode(a) <- "double"
    a
  })
}

# tiff's display path preserves float samples, but normalises integer samples.
# Decode only independently qualified sample types and photometric spaces.
.tiff_raw_read <- function(path) {
  if (!.tiff_available()) cli::cli_abort("Raw TIFF reading requires package tiff; display conversion cannot preserve mask/image samples.")
  imgs <- tryCatch(suppressWarnings(tiff::readTIFF(path,all=TRUE,as.is=FALSE,info=TRUE)),
    error=function(e) cli::cli_abort("Unsupported or invalid raw TIFF encoding: {conditionMessage(e)}"))
  if (!is.list(imgs)) imgs <- list(imgs)
  lapply(imgs,function(a) {
    bits <- attr(a,"bits.per.sample"); format <- attr(a,"sample.format") %||% "uint"
    colour <- attr(a,"color.space")
    if (length(bits)!=1L || !format %in% c("uint","int","float") ||
        !colour %in% c("black is zero","RGB") ||
        !(length(dim(a)) %in% c(2L,3L)) ||
        prod(dim(a)) != attr(a,"width") * attr(a,"length") * attr(a,"samples.per.pixel")) {
      cli::cli_abort("Unsupported TIFF sample type, colour space or channel layout; raw samples cannot be guaranteed.")
    }
    if (format == "float") {
      if (!bits %in% c(32L,64L)) cli::cli_abort("Unsupported floating TIFF sample depth.")
    } else {
      if (!bits %in% c(8L,16L)) cli::cli_abort("Unsupported integer TIFF sample depth; raw decoder supports 8/16-bit integers.")
      a <- a * (2^bits-1)
      if (any(!is.finite(a)) || any(abs(a-round(a)) > 1e-7) || any(a < 0 | a > 2^bits-1)) cli::cli_abort("TIFF decoder did not return exact integer sample codes.")
      a <- round(a)
      if (format == "int") a[a >= 2^(bits-1)] <- a[a >= 2^(bits-1)] - 2^bits
    }
    attr(a,"raw_dtype") <- paste0(format,bits)
    a
  })
}

# Parse channel names from an OME-XML / qptiff ImageDescription, degrading
# gracefully. Never errors.
.tiff_channel_names <- function(desc, n) {
  default <- paste0("Channel ", seq_len(n))
  if (is.null(desc) || !nzchar(desc)) {
    return(default)
  }
  nm <- tryCatch(
    {
      if (requireNamespace("xml2", quietly = TRUE) && grepl("<", desc, fixed = TRUE)) {
        doc <- xml2::read_xml(desc)
        ch <- xml2::xml_find_all(doc, "//*[local-name()='Channel']")
        vals <- xml2::xml_attr(ch, "Name")
        vals[!is.na(vals)]
      } else {
        m <- regmatches(desc, gregexpr("<Name>([^<]*)</Name>", desc, perl = TRUE))[[1]]
        sub("<Name>([^<]*)</Name>", "\\1", m)
      }
    },
    error = function(e) character(0)
  )
  if (length(nm) == n) nm else default
}

.tiff_read <- function(path, ...) {
  if (!requireNamespace("tiff", quietly = TRUE)) {
    cli::cli_abort(c(
      "The {.val tiff} backend requires package {.pkg tiff}.",
      "i" = "Install it with {.code install.packages(\"tiff\")}."
    ))
  }
  # Multi-channel TIFFs can emit benign libtiff ExtraSamples warnings; the read
  # itself is correct, so they are suppressed here.
  raw <- .tiff_raw_read(path)
  desc <- attr(if (is.list(raw)) raw[[1]] else raw, "description")
  dtype <- vapply(raw,attr,character(1),which="raw_dtype")
  if (length(unique(dtype))!=1L) cli::cli_abort("TIFF directories have incompatible sample types.")
  levels <- .tiff_to_levels(raw)
  level_dims <- lapply(levels, function(a) c(dim(a)[2], dim(a)[1]))
  nb <- dim(levels[[1]])[3]
  if (any(vapply(levels,function(a) dim(a)[3]!=nb,logical(1))) ||
      (length(levels)>1L && any(vapply(seq.int(2L,length(levels)),function(i)
        any(level_dims[[i]]>level_dims[[i-1L]]) || all(level_dims[[i]]==level_dims[[i-1L]]),logical(1))))) {
    cli::cli_abort("Ambiguous TIFF directories: only a consistent decreasing pyramid is supported; use a format-specific reader for independent planes.")
  }
  new_annot_image(
    source = path, backend = "tiff",
    dims = level_dims[[1]], n_levels = length(levels), level_dims = level_dims,
    n_bands = nb, band_names = .tiff_channel_names(desc, nb),
    pixel_size = c(1, 1), pixel_unit = "px", dtype = dtype[1],
    handle = list(levels = levels), meta = list(reader_contract = list(axes="yxb",samples="raw-scalar-v1"))
  )
}

.tiff_tile <- function(img, level, xrange, yrange, bands) {
  arr <- img$handle$levels[[level + 1L]]
  ys <- yrange[1]:yrange[2]
  xs <- xrange[1]:xrange[2]
  bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
  arr[ys, xs, bs, drop = FALSE]
}

.tiff_detect <- function(path) {
  grepl("\\.(tiff?)$", path, ignore.case = TRUE) &&
    !grepl("\\.(ome\\.tif|ome\\.tiff|qptiff)$", path, ignore.case = TRUE)
}

.tiff_available <- function() requireNamespace("tiff", quietly = TRUE)

# ---- ometiff backend (RBioFormats) -----------------------------------------

.ometiff_read <- function(path, series = NULL, ...) {
  if (!requireNamespace("RBioFormats", quietly=TRUE) || !requireNamespace("xml2",quietly=TRUE)) {
    cli::cli_abort("The ometiff backend requires packages RBioFormats and xml2 to preserve axes and calibration.")
  }
  files <- .source_files(c(image=path))
  .read_telemetry_add(native_metadata_calls=1,native_file_bytes=NA_real_)
  meta <- RBioFormats::read.metadata(path)
  records <- RBioFormats::coreMetadata(meta)
  if (!is.null(records$sizeX)) records <- list(records)
  available_series <- unique(vapply(records,function(x) as.integer(x$series),integer(1)))
  if (is.null(series)) {
    if (length(available_series)!=1L) cli::cli_abort("Multiple OME image series require explicit series selection.")
    series <- available_series[1]
  }
  if (!is.numeric(series) || length(series)!=1L || is.na(series) || !series %in% available_series) cli::cli_abort("Invalid OME series selection.")
  records <- Filter(function(x) x$series==series,records)
  records <- unname(records[order(vapply(records,function(x) as.integer(x$resolutionLevel),integer(1)))])
  if (any(vapply(records,function(x) x$sizeZ!=1L || x$sizeT!=1L,logical(1)))) {
    cli::cli_abort("OME Z/time axes are unsupported; select/export a single Z and time plane explicitly.")
  }
  nb <- records[[1]]$sizeC; dtype <- records[[1]]$pixelType
  if (any(vapply(records,function(x) x$sizeC!=nb || x$pixelType!=dtype,logical(1)))) cli::cli_abort("Inconsistent OME resolution channel/sample metadata.")
  level_dims <- lapply(records,function(x) as.integer(c(x$sizeX,x$sizeY)))
  .read_telemetry_add(native_metadata_calls=1, native_file_bytes=NA_real_)
  doc <- xml2::read_xml(RBioFormats::read.omexml(path))
  if (!identical(files,.source_files(c(image=path)))) cli::cli_abort("Image source changed during metadata open.")
  images <- xml2::xml_find_all(doc,"/*[local-name()='OME']/*[local-name()='Image']")
  if (series > length(images)) cli::cli_abort("OME XML has no metadata for selected series.")
  pixels <- xml2::xml_find_first(images[[series]],"./*[local-name()='Pixels']")
  channels <- xml2::xml_find_all(pixels,"./*[local-name()='Channel']")
  names <- xml2::xml_attr(channels,"Name")
  bn <- if(length(names)==nb) names else rep(NA_character_,nb)
  values <- suppressWarnings(as.numeric(xml2::xml_attr(channels,"EmissionWavelength")))
  units <- xml2::xml_attr(channels,"EmissionWavelengthUnit")
  wavelengths <- NULL; wavelength_unit <- NULL; wavelength_status <- "missing"
  if (length(values)==nb && all(is.finite(values) & values>0) && !anyNA(units) && length(unique(units))==1L) {
    wavelengths <- values;wavelength_unit<-units[1];wavelength_status<-"declared"
  }
  # xml_attr takes a single attribute name; collect the two axes explicitly.
  physical <- vapply(c("PhysicalSizeX","PhysicalSizeY"),function(k) suppressWarnings(as.numeric(xml2::xml_attr(pixels,k))),numeric(1))
  physical_units <- vapply(c("PhysicalSizeXUnit","PhysicalSizeYUnit"),function(k) xml2::xml_attr(pixels,k),character(1))
  pixel_size <- c(1,1);pixel_unit <- "px";calibration_status <- "missing"
  if (all(is.finite(physical) & physical>0) && !anyNA(physical_units) && length(unique(physical_units))==1L) {
    pixel_size<-unname(physical);pixel_unit<-unname(physical_units[1]);calibration_status<-"declared"
  }
  new_annot_image(source=path,backend="ometiff",dims=level_dims[[1]],
    n_levels=length(records),level_dims=level_dims,n_bands=nb,band_names=bn,
    wavelengths=wavelengths,wavelength_unit=wavelength_unit,
    pixel_size=pixel_size,pixel_unit=pixel_unit,dtype=dtype,
    handle=list(windowed=TRUE,path=path,series=series,layout=records,files=files),
    meta=list(capabilities=.window_capabilities("native"),reader_contract=list(axes="yxb",samples="raw-scalar-v1"),series=as.integer(series),
      calibration_status=calibration_status,wavelength_status=wavelength_status))
}

.ometiff_tile <- function(img, level, xrange, yrange, bands) {
  if (isTRUE(img$handle[["windowed"]])) return(.ome_window(img,level,xrange,yrange,bands))
  arr <- img$handle$levels[[level + 1L]]
  ys <- yrange[1]:yrange[2]
  xs <- xrange[1]:xrange[2]
  bs <- if (is.null(bands)) seq_len(img$n_bands) else bands
  arr[ys, xs, bs, drop = FALSE]
}

.ometiff_detect <- function(path) {
  grepl("\\.(ome\\.tif|ome\\.tiff|qptiff)$", path, ignore.case = TRUE)
}

.ometiff_available <- function() requireNamespace("RBioFormats", quietly = TRUE) && requireNamespace("xml2", quietly = TRUE)
