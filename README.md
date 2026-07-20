<!-- README.md is generated from README.Rmd. Please edit that file -->

# annotatR <img src="man/figures/logo.png" align="right" height="139" alt="annotatR logo" />

<!-- badges: start -->

[![R-CMD-check](https://github.com/CTTIR/annotatR/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/CTTIR/annotatR/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/CTTIR/annotatR/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/CTTIR/annotatR/actions/workflows/pkgdown.yaml)
[![Codecov test
coverage](https://codecov.io/gh/CTTIR/annotatR/graph/badge.svg)](https://app.codecov.io/gh/CTTIR/annotatR)
[![License:
MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

**annotatR** provides multi-layer region-of-interest (ROI) annotation for
whole-slide microscopy images, hyperspectral data cubes, and conventional
rasters. Annotations are validated simple-feature geometries stored in
image pixel coordinates, and rasterise to binary, labelled, or
multi-class integer masks for downstream segmentation and classification.

## Installation

You can install the development version of annotatR from
[GitHub](https://github.com/CTTIR/annotatR) with:

``` r
# install.packages("pak")
pak::pak("CTTIR/annotatR")
```

## Acknowledgements

annotatR builds on [OpenSeadragon](https://openseadragon.github.io/),
[Annotorious](https://annotorious.github.io/), and the
[`sf`](https://r-spatial.github.io/sf/) and
[`stars`](https://r-spatial.github.io/stars/) packages.
