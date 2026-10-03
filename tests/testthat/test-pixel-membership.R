# Literal grids below are derived from geometric inequalities, independently of
# either raster engine. They catch fast-path false positives, floating shifts,
# hole filling, orientation dependence, and single/batch membership drift.
pixel_grid <- function(rows) {
  matrix(unlist(strsplit(rows, "", fixed = TRUE)) == "1",
         nrow = length(rows), byrow = TRUE)
}

membership_fixtures <- function() {
  poly <- function(x) sf::st_polygon(list(rbind(x, x[1, ])))
  ring <- function(x0, y0, x1, y1) rbind(c(x0,y0), c(x1,y0), c(x1,y1), c(x0,y1), c(x0,y0))
  list(
    diagonal = list(g = poly(rbind(c(0,0),c(5,0),c(5,5))),
                    rows = c("11111","01111","00111","00011","00001")),
    descending = list(g = poly(rbind(c(0,0),c(5,0),c(0,5))),
                      rows = c("11110","11100","11000","10000","00000")),
    non_tie = list(g = poly(rbind(c(0,0),c(4,0),c(0,2.8))),
                   rows = c("11100","11000","00000","00000","00000")),
    vertex_ties = list(g = poly(rbind(c(.5,.5),c(4.5,.5),c(.5,4.5))),
                       rows = c("11110","11100","11000","10000","00000")),
    clipped = list(g = poly(rbind(c(-2,-2),c(3,-2),c(3,3))),
                   rows = c("11100","01100","00100","00000","00000")),
    thin_diagonal = list(g = poly(rbind(c(0,0),c(.1,0),c(5.1,5),c(5,5))),
                         rows = c("10000","01000","00100","00010","00001")),
    thin_miss = list(g = sf::st_polygon(list(ring(.5+5e-8,0,.5+1e-7,5))),
                     rows = rep("00000",5)),
    thin_hit = list(g = sf::st_polygon(list(ring(.5-5e-8,0,.5+5e-8,5))),
                    rows = rep("10000",5)),
    hole = list(g = sf::st_polygon(list(ring(.5,.5,4.5,4.5), ring(1.5,1.5,3.5,3.5))),
                rows = c("11110","10010","10010","11110","00000"))
  )
}

test_that("centre membership matches literal grids in every polygon path", {
  for (name in names(membership_fixtures())) {
    case <- membership_fixtures()[[name]]
    expected <- pixel_grid(case$rows)
    for (reverse in c(FALSE, TRUE)) {
      rings <- if (reverse) lapply(case$g, function(r) r[nrow(r):1, , drop = FALSE]) else unclass(case$g)
      polygon <- sf::st_polygon(rings)
      # A single-component MultiPolygon bypasses the rectangle short circuit.
      for (g in list(polygon, sf::st_multipolygon(list(rings)))) {
        roi <- new_annot_roi(sf::st_sfc(g), "subject", "subject", 0L)
        layer <- at_layer_add(at_layer_add(at_layer("L"), roi), at_roi_rect(6,6,7,7,"extra"))
        for (engine in c("stars", if (requireNamespace("terra", quietly = TRUE)) "terra")) {
          expect_identical(as.matrix(at_mask(roi, dims=c(5,5), engine=engine)), expected, info=name)
          for (policy in c("first", "last")) {
            expect_identical(as.matrix(at_mask(layer, "labelled", dims=c(5,5), engine=engine,
                                               overlap=policy)) == 1L, expected, info=name)
          }
        }
      }
    }
  }
})

test_that("rectangle optimization rejects triangles, bowties and near rectangles", {
  triangle <- sf::st_polygon(list(rbind(c(0,0),c(5,0),c(5,5),c(0,0))))
  bowtie <- sf::st_polygon(list(rbind(c(0,0),c(5,5),c(5,0),c(0,5),c(0,0))))
  skew <- sf::st_polygon(list(rbind(c(0,0),c(5,0),c(5+1e-10,5),c(0,5),c(0,0))))
  for (g in list(triangle, bowtie, skew)) expect_null(.cover_shortcircuit(g,c(5,5)))
})

test_that("point masks and extraction select the same half-open containing cell", {
  img <- tiny_image()
  img$handle <- list(data = array(seq_len(100), c(10,10,1)))
  .tile_cache_clear(); withr::defer(.tile_cache_clear())
  cases <- list(list(xy=c(5,5), ij=c(6,6), value=56),
                list(xy=c(0,0), ij=c(1,1), value=1),
                list(xy=c(9.999,9.999), ij=c(10,10), value=100),
                list(xy=c(5-5e-8,5+5e-8), ij=c(6,5), value=46),
                list(xy=c(-5e-8,5), ij=NULL), list(xy=c(10,5), ij=NULL))
  for (case in cases) {
    roi <- at_roi_point(case$xy[1],case$xy[2],"p")
    project <- at_project(img, at_layer_add(at_layer("L"), roi))
    expected <- matrix(FALSE,10,10)
    if (!is.null(case$ij)) expected[matrix(case$ij,nrow=1)] <- TRUE
    expect_identical(as.matrix(at_mask(project)),expected)
    px <- at_extract_pixels(project)
    summary <- at_extract(project)
    expect_equal(nrow(px),as.integer(!is.null(case$ij)))
    expect_equal(nrow(summary),as.integer(!is.null(case$ij)))
    if (!is.null(case$ij)) {
      expect_equal(px$value,case$value)
      expect_equal(c(px$y,px$x),case$ij)
      expect_equal(summary$value,case$value)
      expect_equal(summary$n_px,1L)
    }
  }
})

test_that("polygon tile extraction keeps the independently specified pixel support", {
  img <- new_annot_image("membership", "raster", c(5L,5L), 1L, list(c(5L,5L)), 1L,
                         handle=list(data=array(seq_len(25),c(5,5,1))))
  .tile_cache_clear(); withr::defer(.tile_cache_clear())
  for (case in membership_fixtures()) {
    roi <- new_annot_roi(sf::st_sfc(case$g),"subject","subject",0L)
    p <- at_project(img,at_layer_add(at_layer("L"),roi))
    want <- which(pixel_grid(case$rows),arr.ind=TRUE)
    px <- at_extract_pixels(p)
    expect_equal(px$y,as.double(want[,1]))
    expect_equal(px$x,as.double(want[,2]))
    expect_equal(px$value,as.double((want[,2]-1)*5+want[,1]))
  }
})

test_that("multipoint containing cells agree across engines, batching and extraction", {
  g <- sf::st_multipoint(rbind(c(0,0),c(2,2),c(2.2,2.2),c(5,5),c(-.1,0)))
  roi <- new_annot_roi(sf::st_sfc(g),"points","points",0L)
  img <- tiny_image(); img$handle <- list(data=array(seq_len(100),c(10,10,1)))
  p <- at_project(img,at_layer_add(at_layer("L"),roi))
  expected <- matrix(FALSE,10,10); expected[cbind(c(1,3,6),c(1,3,6))] <- TRUE
  for (engine in c("stars", if (requireNamespace("terra",quietly=TRUE)) "terra")) {
    expect_identical(as.matrix(at_mask(p,engine=engine)),expected)
    more <- at_layer_add(p$layers[[1]],at_roi_rect(20,20,21,21,"extra"))
    expect_identical(as.matrix(at_mask(more,"labelled",dims=c(10,10),engine=engine))==1L,expected)
  }
  expect_equal(at_extract_pixels(p)$value,c(1,23,56))
})

test_that("inferred mask dimensions include integer-coordinate point cells", {
  m <- as.matrix(at_mask(at_roi_point(5,5,"p")))
  expect_identical(dim(m),c(6L,6L))
  expect_equal(sum(m),1L)
  origin <- as.matrix(at_mask(at_roi_point(0,0,"p")))
  expect_identical(origin,matrix(TRUE,1,1))
})

test_that("line extraction bounds retain the selected engine's boundary pixels", {
  img <- tiny_image(); img$handle <- list(data=array(seq_len(100),c(10,10,1)))
  # Lines retain the existing engine convention: the negative shift places an
  # integer vertical line at x=5 in column 5, including its endpoint cells.
  g <- sf::st_linestring(rbind(c(5,5),c(5,8)))
  roi <- new_annot_roi(sf::st_sfc(g),"line","line",0L)
  p <- at_project(img,at_layer_add(at_layer("L"),roi))
  expected <- matrix(FALSE,10,10); expected[5:8,5] <- TRUE
  expect_identical(as.matrix(at_mask(p)),expected)
  expect_equal(at_extract_pixels(p)$value,45:48)
})

test_that("concave rings and multiple polygon components retain separate intervals", {
  ring <- rbind(c(.5,.5),c(4.5,.5),c(4.5,4.5),c(3.5,4.5),c(3.5,1.5),
                c(1.5,1.5),c(1.5,4.5),c(.5,4.5),c(.5,.5))
  expected <- pixel_grid(c("11110","10010","10010","10010","00000"))
  expect_identical(.cover(sf::st_polygon(list(ring)),c(5,5)),expected)
  # The components share a sloping edge; their union fills the square once.
  a <- rbind(c(0,0),c(5,0),c(5,5),c(0,0))
  b <- rbind(c(0,0),c(5,5),c(0,5),c(0,0))
  expect_identical(.cover(sf::st_multipolygon(list(list(a),list(b))),c(5,5)),matrix(TRUE,5,5))
})

test_that("integer triangle diagonal ties match the literal five-pixel oracle", {
  vertices <- rbind(c(19,2),c(14,9),c(3,20))
  expected <- matrix(FALSE,20,20)
  expected[cbind(c(7,8,9,10,11),c(16,15,14,13,12))] <- TRUE
  # Edge x+y=23 excludes its centres: the symbolic sample increases x+y.
  for (reverse in c(FALSE,TRUE)) {
    v <- if (reverse) vertices[3:1,] else vertices
    roi <- new_annot_roi(sf::st_sfc(sf::st_polygon(list(rbind(v,v[1,])))),"triangle","triangle",0L)
    for (engine in c("stars",if (requireNamespace("terra",quietly=TRUE)) "terra")) {
      expect_identical(as.matrix(at_mask(roi,dims=c(20,20),engine=engine)),expected)
    }
  }
})

test_that("triangle full masks and extraction exclude fixture value 157 on a diagonal", {
  img <- new_annot_image("triangle-window","raster",c(30L,30L),1L,list(c(30L,30L)),1L,
                         handle=list(data=array(seq_len(900),c(30,30,1))))
  vertices <- rbind(c(15,29),c(27,28),c(2,3))
  for (reverse in c(FALSE,TRUE)) {
    v <- if (reverse) vertices[3:1,] else vertices
    roi <- new_annot_roi(sf::st_sfc(sf::st_polygon(list(rbind(v,v[1,])))),"triangle","triangle",0L)
    p <- at_project(img,at_layer_add(at_layer("L"),roi))
    px <- at_extract_pixels(p)
    extracted <- matrix(FALSE,30,30); extracted[cbind(px$y,px$x)] <- TRUE
    # The interior has y>x+1. Symbolic (5.5+eps,6.5+eps^2) is outside;
    # matrix[7,6], whose fixture value is 157, must never be extracted.
    expect_false(157 %in% px$value)
    expect_equal(nrow(px),150L)
    expect_equal(at_extract(p,stat="n")$value,150)
    for (engine in c("stars",if (requireNamespace("terra",quietly=TRUE)) "terra")) {
      mask <- as.matrix(at_mask(p,engine=engine))
      expect_false(mask[7,6])
      expect_equal(sum(mask),150L)
      expect_identical(extracted,mask)
    }
  }
})

# Independent convex-polygon oracle: intersect all three directed half-planes,
# rather than scanline crossing parity or a raster engine. Integer vertices and
# half-integer centres keep these small cross products exactly representable.
triangle_halfplanes <- function(v, dims) {
  x <- matrix(rep(seq_len(dims[1])-.5,each=dims[2]),dims[2],dims[1])
  y <- matrix(rep(seq_len(dims[2])-.5,dims[1]),dims[2],dims[1])
  winding <- sign((v[2,1]-v[1,1])*(v[3,2]-v[1,2]) -
                  (v[2,2]-v[1,2])*(v[3,1]-v[1,1]))
  inside <- matrix(TRUE,dims[2],dims[1])
  for (k in 1:3) {
    a <- v[k,]; b <- v[if (k==3) 1 else k+1,]
    dx <- (b[1]-a[1])*winding; dy <- (b[2]-a[2])*winding
    constant <- dx*(y-a[2])-dy*(x-a[1])
    # Lexicographic sign of constant - dy*epsilon + dx*epsilon^2.
    inside <- inside & (constant>0 | (constant==0 & (-dy>0 | (dy==0 & dx>0))))
  }
  inside
}

test_that("translated integer triangles match independent directed half-planes", {
  triangles <- list(rbind(c(19,2),c(14,9),c(3,20)),
                    rbind(c(15,29),c(27,28),c(2,3)),
                    rbind(c(-4,-3),c(12,9),c(2,13)),
                    rbind(c(0,7),c(17,2),c(8,19)))
  img <- new_annot_image("halfplanes","raster",c(40L,40L),1L,list(c(40L,40L)),1L,
                         handle=list(data=array(seq_len(1600),c(40,40,1))))
  for (vertices in triangles) for (offset in list(c(0,0),c(3,5),c(-2,-1))) {
    translated <- sweep(vertices,2,offset,"+")
    expected <- triangle_halfplanes(translated,c(40,40))
    for (reverse in c(FALSE,TRUE)) {
      v <- if (reverse) translated[3:1,] else translated
      roi <- new_annot_roi(sf::st_sfc(sf::st_polygon(list(rbind(v,v[1,])))),"triangle","triangle",0L)
      p <- at_project(img,at_layer_add(at_layer("L"),roi))
      for (engine in c("stars",if (requireNamespace("terra",quietly=TRUE)) "terra")) {
        expect_identical(as.matrix(at_mask(p,engine=engine)),expected)
      }
      px <- at_extract_pixels(p)
      expect_equal(px$value,as.double(which(expected)))
      expect_equal(at_extract(p,stat="n")$value,as.double(sum(expected)))
    }
  }
})

test_that("a rectangle lower edge just above a centre excludes that centre", {
  lower <- .5 + .Machine$double.eps/2
  g <- sf::st_polygon(list(rbind(c(lower,0),c(2,0),c(2,2),c(lower,2),c(lower,0))))
  expected <- matrix(c(FALSE,TRUE,FALSE,TRUE),2,2,byrow=TRUE)
  expect_identical(.cover(g,c(2,2)),expected)
  expect_identical(.cover(sf::st_multipolygon(list(unclass(g))),c(2,2)),expected)
})
