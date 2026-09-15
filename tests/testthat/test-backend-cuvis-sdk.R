# Cubert via the optional CUVIS SDK. Without the SDK the backend must report
# itself unavailable with a reason; the real-data lane needs an installed
# cuvis.r + SDK and a permitted local .cu3s named by ANNOTATR_CUVIS_FIXTURE
# (vendor data is never copied into the package).

test_that("without a usable SDK the cuvis capability is unavailable and reads fail classified", {
  local_mocked_bindings(.cuvis_status = function() {
    list(available = FALSE, reason = "package cuvis.r is not installed")
  })
  expect_false(.cuvis_available())
  caps <- at_interop_capabilities(target = "hsi")$hsi$backends$cuvis
  expect_identical(caps$status, "unavailable")
  expect_identical(caps$reason, "package cuvis.r is not installed")
  f <- withr::local_tempfile(fileext = ".cu3s")
  writeLines("x", f)
  err <- tryCatch(.cuvis_read(f), error = function(e) e)
  expect_s3_class(err, "at_capability_error")
  expect_identical(err$code, "CAPABILITY_UNAVAILABLE")
  expect_match(conditionMessage(err), "ENVI/TIFF export")
  expect_identical(tryCatch(at_cubert_export_envi(f, tempfile()), error = function(e) e$code),
                   "CAPABILITY_UNAVAILABLE")
})

test_that("an installed CUVIS SDK reads a permitted local measurement with provenance", {
  fixture <- Sys.getenv("ANNOTATR_CUVIS_FIXTURE", "")
  skip_if(!nzchar(fixture) || !file.exists(fixture),
          "needs ANNOTATR_CUVIS_FIXTURE pointing to a permitted .cu3s (open: Cubert real-data lane)")
  skip_if_not(.cuvis_status()$available,
              paste("needs cuvis.r with a usable CUVIS SDK:", .cuvis_status()$reason))
  img <- at_read_image(fixture)
  expect_identical(img$backend, "cuvis")
  expect_true(at_is_spectral(img))
  expect_identical(length(at_wavelengths(img)), at_n_bands(img))
  hm <- at_hsi_meta(img)
  expect_identical(hm$vendor, "Cubert")
  expect_true(hm$value_unit %in% c("raw", "reflectance", "radiance", "unknown"))
  expect_match(hm$calibration_digest, "^[0-9a-f]{64}$")
  expect_identical(hm$pan_sharpened, NA)
  expect_match(img$meta$sdk$sdk_version, "SDK")
  d <- at_dims(img)
  tile <- at_tile(img, xrange = c(1, min(4, d[1])), yrange = c(1, min(3, d[2])))
  expect_identical(dim(tile)[3], at_n_bands(img))
  expect_true(all(is.finite(tile)))
})
