test_that("every shipped schema parses and uses only supported keywords", {
  root <- system.file("schema", package = "annotatR")
  files <- list.files(root, pattern = "\\.schema\\.json$", recursive = TRUE)
  expect_gte(length(files), 12L)
  for (f in files) {
    fam <- dirname(f)
    nm <- sub("\\.schema\\.json$", "", basename(f))
    expect_type(.schema_load(fam, nm), "list")
  }
})

test_that("the validator enforces types, required fields, enums and patterns", {
  schema <- list(
    type = "object", required = list("id", "n"), additionalProperties = FALSE,
    properties = list(
      id = list(type = "string", pattern = "^[a-z]+$"),
      n = list(type = "integer", minimum = 1),
      kind = list(type = "string", enum = list("a", "b")),
      tags = list(type = "array", maxItems = 2, items = list(type = "string")),
      extensions = list(type = "object")
    )
  )
  ok <- list(id = "abc", n = 2L, kind = "a", tags = list("x"), extensions = list(any = 1))
  expect_length(.schema_validate(ok, schema), 0L)
  expect_match(.schema_validate(list(id = "abc"), schema), "missing required property 'n'")
  expect_match(.schema_validate(list(id = "ABC", n = 1L), schema), "pattern")
  expect_match(.schema_validate(list(id = "a", n = 0L), schema), "below minimum")
  expect_match(.schema_validate(list(id = "a", n = 1.5), schema), "expected type integer")
  expect_match(.schema_validate(list(id = "a", n = 1L, kind = "z"), schema), "one of")
  expect_match(.schema_validate(list(id = "a", n = 1L, other = 1L), schema), "unknown property")
  expect_match(.schema_validate(list(id = "a", n = 1L, tags = list("x", "y", "z")), schema),
               "too many items")
})

test_that("local references and oneOf are resolved", {
  schema <- list(definitions = list(pos = list(type = "integer", minimum = 0)),
                 type = "object", properties = list(x = list(`$ref` = "#/definitions/pos")),
                 oneOf = list(list(required = list("x")), list(required = list("y"))))
  expect_length(.schema_validate(list(x = 1L), schema), 0L)
  expect_match(.schema_validate(list(x = -1L), schema), "below minimum")
  expect_match(.schema_validate(list(x = 1L, y = 2L), schema), "exactly one")
})

test_that("unsupported schema keywords are refused rather than ignored", {
  expect_error(.schema_check_keywords(list(type = "object", patternProperties = list()), "t"),
               "unsupported keyword")
})

test_that("major versions other than 1 are rejected with PROTOCOL_MISMATCH", {
  expect_invisible(.check_major_version("1.3", 1L, "doc"))
  err <- tryCatch(.check_major_version("2.0", 1L, "doc"), error = function(e) e)
  expect_s3_class(err, "at_protocol_error")
  expect_identical(err$code, "PROTOCOL_MISMATCH")
  expect_error(.check_major_version("one", 1L, "doc"), class = "at_protocol_error")
})
