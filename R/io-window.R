# Counters are logical bytes delivered by the binary reader, never OS traffic.
# Native APIs expose decoded requests only; their encoded I/O remains unknown.
.read_io <- new.env(parent=emptyenv())
.read_telemetry_reset <- function() {
  .read_io$counts <- list(binary_bytes=0, binary_calls=0, native_metadata_calls=0,
    native_window_calls=0, native_file_bytes=0, decoded_bytes=0)
  invisible(NULL)
}
.read_telemetry <- function() {
  if (is.null(.read_io$counts)) .read_telemetry_reset()
  .read_io$counts
}
.read_telemetry_add <- function(...) {
  counts <- .read_telemetry()
  for (k in names(list(...))) counts[[k]] <- counts[[k]] + list(...)[[k]]
  .read_io$counts <- counts
  invisible(NULL)
}
.window_read_raw <- function(con,n) {
  x <- readBin(con,'raw',n=n)
  .read_telemetry_add(binary_bytes=length(x),binary_calls=1)
  if (length(x)!=n) cli::cli_abort('Short/truncated window or header.')
  x
}
.window_capabilities <- function(io) list(metadata_only=TRUE,window_read=TRUE,
  samples='raw-scalar-v1',io=io,lifecycle='per-read connections')
.memory_snapshot <- function(img) {
  h <- img[['handle']]
  is.list(h) && (is.array(h[['data']]) ||
    (is.list(h[['levels']]) && length(h[['levels']])>0L && all(vapply(h[['levels']],is.array,logical(1)))))
}
.window_budget <- function(nx,ny,nb) {
  n <- as.double(nx)*ny*nb
  if (!is.finite(n) || n > .Machine$integer.max) cli::cli_abort('Window exceeds supported array indexing limits.')
  .read_budget(n*8)
  n
}
.binary_window <- function(img,xrange,yrange,bands) {
  h <- img$handle; l <- h$layout; spec <- h$spec
  nx <- l$dims[1]; ny <- l$dims[2]; nb <- l$dims[3]
  n <- .window_budget(diff(xrange)+1,diff(yrange)+1,if(is.null(bands)) nb else length(bands))
  xs <- seq.int(xrange[1],xrange[2]);ys <- seq.int(yrange[1],yrange[2])
  bs <- bands %||% seq_len(nb); unique_bs <- sort(unique(bs))
  out <- array(0,c(length(ys),length(xs),length(unique_bs)))
  con <- file(h$path,'rb');on.exit(close(con))
  run <- function(index,count) {
    seek(con,where=l$offset+spec$size*index,origin='start')
    raw <- .window_read_raw(con,count*spec$size)
    if (spec$what=='integer') .decode_integer_bytes(raw,spec$size,spec$signed,l$endian)
    else readBin(raw,'double',n=count,size=spec$size,endian=l$endian)
  }
  # BSQ/BIL have x-contiguous scanline runs. Band-fastest layouts read only
  # requested contiguous band runs at each pixel; no full scanline/cube buffer.
  if (l$interleave %in% c('bsq','bil')) {
    for (b in seq_along(unique_bs)) for (y in seq_along(ys)) {
      index <- if (l$interleave=='bsq') (unique_bs[b]-1)*as.double(nx)*ny+(ys[y]-1)*as.double(nx)+xs[1]-1
        else (ys[y]-1)*as.double(nb)*nx+(unique_bs[b]-1)*as.double(nx)+xs[1]-1
      out[y,,b] <- run(index,length(xs))
    }
  } else if (length(unique_bs)==nb) {
    if (l$interleave=='bip') {
      for (y in seq_along(ys)) {
        index<-((ys[y]-1)*as.double(nx)+xs[1]-1)*nb
        out[y,,]<-t(matrix(run(index,length(xs)*nb),nrow=nb))
      }
    } else {
      for (x in seq_along(xs)) {
        index<-((xs[x]-1)*as.double(ny)+ys[1]-1)*nb
        out[,x,]<-t(matrix(run(index,length(ys)*nb),nrow=nb))
      }
    }
  } else {
    groups <- split(seq_along(unique_bs),cumsum(c(TRUE,diff(unique_bs)!=1)))
    for (x in seq_along(xs)) for (y in seq_along(ys)) for (g in groups) {
      pixel <- if (l$interleave=='speccube') (xs[x]-1)*as.double(ny)+ys[y]-1 else (ys[y]-1)*as.double(nx)+xs[x]-1
      out[y,x,g] <- run(pixel*nb+unique_bs[g[1]]-1,length(g))
    }
  }
  .read_telemetry_add(decoded_bytes=n*8)
  out[,,match(bs,unique_bs),drop=FALSE]
}
.ome_window <- function(img,level,xrange,yrange,bands) {
  h <- img$handle;core <- h$layout[[level+1L]]
  n<-.window_budget(diff(xrange)+1,diff(yrange)+1,if(is.null(bands)) img$n_bands else length(bands))
  xs<-seq.int(xrange[1],xrange[2]);ys<-seq.int(yrange[1],yrange[2])
  bs<-bands %||% seq_len(img$n_bands);ub<-sort(unique(bs))
  .read_telemetry_add(native_window_calls=1,native_file_bytes=NA_real_)
  a<-as.array(RBioFormats::read.image(h$path,series=h$series,resolution=core$resolutionLevel,
    subset=list(x=xs,y=ys,c=ub),normalize=FALSE,read.metadata=FALSE))
  .read_telemetry_add(decoded_bytes=n*8)
  want<-c(length(xs),length(ys),length(ub))
  if (length(a)!=prod(want) || !identical(as.integer(dim(a)[1:2]),as.integer(want[1:2]))) cli::cli_abort('OME window axes disagree with the request.')
  a<-aperm(array(a,dim=want),c(2,1,3));storage.mode(a)<-'double'
  a[,,match(bs,ub),drop=FALSE]
}

#' Inspect the effective reading capabilities of an image
#'
#' @param x An annot_image or annot_project.
#' @return A list with metadata_only, window_read, samples, io and optional
#'   lifecycle fields. Unknown third-party capabilities remain NA/unknown.
#'   Retained arrays report memory access even for normally windowed backends.
#' @export
at_image_capabilities <- function(x) {
  img <- if (inherits(x,'annot_project')) x$image else x
  .check_image(img)
  cap <- img[['meta']][['capabilities']] %||% at_backend_get(img[["backend"]])$capabilities
  if (.memory_snapshot(img)) {
    cap$metadata_only<-FALSE;cap$window_read<-FALSE;cap$io<-'memory'
    cap$lifecycle<-'retained pixel snapshot'
  }
  cap
}

#' Release an image handle
#'
#' @param x An annot_image or annot_project.
#' @return The image or project with its runtime handle released. Assign the
#'   returned value. Future tile access reopens a verified source; releasing a
#'   retained pixel snapshot loses access to those old pixels if its source has
#'   changed or cannot be reopened. Built-in window readers close connections
#'   after each read and have no persistent native connection to release.
#' @export
at_close_image <- function(x) {
  project <- inherits(x,'annot_project');img<-if(project) x$image else x
  .check_image(img)
  close_fn<-at_backend_get(img[["backend"]])[['close_fn']]
  if (!is.null(img[['handle']]) && is.function(close_fn)) close_fn(img)
  img$handle<-NULL;img$cache_identity<-.new_identity_id('closed')
  if(project) {x$image<-img;x} else img
}
