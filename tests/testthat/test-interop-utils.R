# Canonical JSON and SHA-256 are checked against reference vectors computed
# independently with Python's json.dumps(sort_keys=True, separators=(",", ":"))
# and hashlib (data-raw/interop-fixtures/make_canonical_vectors.py).

test_that("canonical JSON and its SHA-256 match the independent Python vectors", {
  v <- jsonlite::fromJSON(test_path("fixtures", "interop", "canonical-json-vectors.json"),
                          simplifyVector = FALSE)
  cases <- setdiff(names(v), "_generator")
  expect_gte(length(cases), 4L)
  for (nm in cases) {
    expect_identical(.canonical_json(v[[nm]]$value), v[[nm]]$canonical, label = nm)
    expect_identical(.sha256_bytes(.canonical_json(v[[nm]]$value)), v[[nm]]$sha256, label = nm)
  }
})

test_that("SHA-256 matches the FIPS 180-2 test vector for 'abc'", {
  expect_identical(.sha256_bytes("abc"),
                   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  f <- withr::local_tempfile()
  writeBin(charToRaw("abc"), f)
  expect_identical(.sha256_file(f),
                   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
})

test_that("canonical JSON orders keys by bytes and refuses non-finite numbers", {
  expect_identical(.canonical_json(list(b = 1L, a = "x", B = TRUE)), '{"B":true,"a":"x","b":1}')
  expect_identical(.canonical_json(list(x = c(1.5, 2))), '{"x":[1.5,2]}')
  expect_identical(.canonical_json(list(n = NULL, e = list(), o = .json_object())),
                   '{"e":[],"n":null,"o":{}}')
  expect_identical(.canonical_json("tab\tq\"\\"), '"tab\\tq\\"\\\\"')
  expect_error(.canonical_json(list(x = Inf)), class = "at_validation_error")
  expect_error(.canonical_json(list(a = 1, a = 2)), class = "at_validation_error")
})

test_that("classified conditions carry class and code", {
  cnd <- tryCatch(.at_abort("nope", class = "conflict", code = "REVISION_CONFLICT"),
                  error = function(e) e)
  expect_s3_class(cnd, "at_conflict_error")
  expect_s3_class(cnd, "at_error")
  expect_identical(cnd$code, "REVISION_CONFLICT")
  expect_identical(.condition_code(simpleError("x")), "INTERNAL_ERROR")
})

test_that("safe components and relative-path checks block traversal", {
  expect_identical(.safe_component(c("../escaped", "a/b", "", "..", "Gewebe ä")),
                   c("escaped", "a_b", "item", "item", "Gewebe_a"))
  expect_identical(.unique_components(c("a", "A", "a")), c("a", "A_2", "a_3"))
  expect_true(.is_clean_relative("masks/a.tif"))
  expect_false(.is_clean_relative("/etc/passwd"))
  expect_false(.is_clean_relative("../x"))
  expect_false(.is_clean_relative("a/../b"))
  expect_false(.is_clean_relative("C:/x"))
  expect_false(.is_clean_relative("a//b"))
})

test_that("paths are resolved only under the negotiated root", {
  root <- withr::local_tempdir()
  outside <- withr::local_tempdir()
  writeLines("x", file.path(root, "in.txt"))
  writeLines("y", file.path(outside, "out.txt"))
  expect_identical(basename(.resolve_under_root(root, "in.txt")), "in.txt")
  expect_error(.resolve_under_root(root, "../out.txt"), class = "at_io_error")
  expect_error(.resolve_under_root(root, file.path(outside, "out.txt")), class = "at_io_error")
  expect_error(.resolve_under_root(root, "missing.txt"), class = "at_io_error")
  skip_on_os("windows")
  file.symlink(file.path(outside, "out.txt"), file.path(root, "link.txt"))
  err <- tryCatch(.resolve_under_root(root, "link.txt"), error = function(e) e)
  expect_identical(err$code, "PATH_OUTSIDE_ROOT")
})

test_that("identifiers are well-formed and leave the RNG stream untouched", {
  set.seed(42)
  before <- .Random.seed
  u <- .uuid()
  expect_match(u, "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
  expect_match(.random_hex(32L), "^[0-9a-f]{64}$")
  expect_identical(.Random.seed, before)
})

test_that("atomic JSON writes leave no temporary files", {
  d <- withr::local_tempdir()
  .write_json_atomic(list(a = 1L), file.path(d, "x.json"))
  expect_identical(list.files(d, all.files = TRUE, no.. = TRUE), "x.json")
  expect_identical(jsonlite::read_json(file.path(d, "x.json"))$a, 1L)
})
