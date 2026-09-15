test_that("file and R-API profiles are supported; control and app stay planned without a qualified client", {
  caps <- at_interop_capabilities()
  expect_s3_class(caps, "at_capabilities")
  expect_identical(caps$schema, "annotatr-capabilities-v1")
  expect_identical(caps$consumer, "qupflowR")
  expect_identical(caps$profiles$I0$status, "supported")
  expect_identical(caps$profiles$I1$status, "supported")
  expect_length(.qualified_clients, 0L)
  for (p in c("I2", "I3")) {
    expect_true(caps$profiles[[p]]$implemented)
    expect_true(caps$profiles[[p]]$status %in% c("planned", "unavailable"))
    expect_false(is.na(caps$profiles[[p]]$reason))
  }
})

test_that("a missing control runtime is reported as unavailable with a reason", {
  local_mocked_bindings(.control_runtime_status = function() {
    list(available = FALSE, reason = "missing package(s): httpuv")
  })
  caps <- at_interop_capabilities(target = "control")
  expect_identical(caps$profiles$I2$status, "unavailable")
  expect_match(caps$profiles$I2$reason, "httpuv")
  expect_false(caps$control$available)
})

test_that("targets select sections and the digest covers the report", {
  pkg <- at_interop_capabilities(target = "package")
  expect_null(pkg$hsi)
  expect_false(is.null(pkg$package))
  all <- at_interop_capabilities()
  expect_true(all(c("package", "hsi", "app", "control") %in% names(all)))
  body <- unclass(all)
  body$digest <- NULL
  expect_identical(all$digest, .sha256_bytes(.canonical_json(body)))
  expect_identical(at_interop_capabilities()$digest, all$digest)
  expect_error(at_interop_capabilities(target = "bogus"), class = "at_validation_error")
})

test_that("HSI backend capabilities reflect installation and window reading", {
  hsi <- at_interop_capabilities(target = "hsi")$hsi
  expect_true(hsi$backends$envi$window_read)
  expect_true(hsi$backends$tivita$window_read)
  expect_identical(hsi$backends$cuvis$available, .cuvis_status()$available)
  if (!.cuvis_status()$available) {
    expect_identical(hsi$backends$cuvis$status, "unavailable")
  }
  expect_true("normalized_difference" %in% unlist(hsi$band_operations))
})

test_that("control capabilities list the typed operations and no code-execution endpoint", {
  cc <- at_control_capabilities()
  expect_identical(cc$protocol, "annotatr-control-v1")
  expect_setequal(unlist(cc$operations), c("session.load", "session.save", "context.goto",
                                           "context.view", "context.selection",
                                           "annotations.stage", "annotations.commit",
                                           "mask.preview", "export", "training.export", "close"))
  expect_false(any(grepl("eval|shell|python|dom", unlist(cc$endpoints), ignore.case = TRUE)))
  expect_true(all(grepl("^[0-9a-f]{64}$", unlist(cc$schemas))))
  expect_output(print(at_interop_capabilities()), "I0 supported")
})
