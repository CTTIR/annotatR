# List registered image backends

List registered image backends

## Usage

``` r
at_backend_list(call = rlang::caller_env())
```

## Arguments

- call:

  The calling environment, for error reporting.

## Value

A [tibble::tibble](https://tibble.tidyverse.org/reference/tibble.html)
with columns `name` (character), `description` (character), `extensions`
(character, comma-separated), and `available` (logical). A 0-row tibble
with these columns when nothing is registered.

## See also

Other backends:
[`at_backend_detect()`](https://cttir.github.io/annotatR/reference/at_backend_detect.md),
[`at_backend_get()`](https://cttir.github.io/annotatR/reference/at_backend_get.md),
[`at_backend_register()`](https://cttir.github.io/annotatR/reference/at_backend_register.md),
[`at_read_image()`](https://cttir.github.io/annotatR/reference/at_read_image.md),
[`at_tile()`](https://cttir.github.io/annotatR/reference/at_tile.md)

## Examples

``` r
at_backend_list()
#> # A tibble: 6 × 4
#>   name    description                                 extensions       available
#>   <chr>   <chr>                                       <chr>            <lgl>    
#> 1 cuvis   Cubert hyperspectral (cuvis.r)              cu3, cu3s        FALSE    
#> 2 envi    ENVI header + binary cube                   hdr, dat, img, … TRUE     
#> 3 ometiff OME-TIFF and qptiff (RBioFormats)           ome.tif, ome.ti… TRUE     
#> 4 raster  PNG, JPEG, and single-plane TIFF            png, jpg, jpeg,… TRUE     
#> 5 tiff    Pyramidal / multi-directory TIFF            tif, tiff        TRUE     
#> 6 tivita  Diaspective Vision Tivita (ENVI-compatible) dat, hdr         TRUE     
```
