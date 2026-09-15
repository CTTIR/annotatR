# A small, dependency-free JSON Schema (draft-07 subset) validator. The schemas
# shipped under inst/schema/ are the single source of truth for the handoff and
# control documents; this validator interprets exactly the keywords they use:
# type, enum, const, required, properties, additionalProperties, items,
# minItems, maxItems, minLength, maxLength, pattern, minimum, maximum,
# anyOf, oneOf and local `$ref` ("#/definitions/..."). Unsupported keywords
# are rejected when a schema is loaded, so a schema can never silently validate
# less than it states. None of this is exported.

.schema_keywords <- c(
  "$schema", "$id", "$comment", "title", "description", "default", "examples",
  "definitions", "type", "enum", "const", "required", "properties",
  "additionalProperties", "items", "minItems", "maxItems", "minLength",
  "maxLength", "pattern", "minimum", "maximum", "anyOf", "oneOf", "$ref", "format"
)

.schema_cache <- new.env(parent = emptyenv())

# Path of a shipped schema, e.g. .schema_path("annotatr-control-v1", "command").
.schema_path <- function(family, name) {
  system.file("schema", family, paste0(name, ".schema.json"), package = "annotatR",
              mustWork = TRUE)
}

# Load (and cache) a shipped schema after checking it only uses supported keywords.
.schema_load <- function(family, name) {
  key <- paste(family, name, sep = "/")
  if (!is.null(.schema_cache[[key]])) {
    return(.schema_cache[[key]])
  }
  schema <- jsonlite::fromJSON(.schema_path(family, name), simplifyVector = FALSE)
  .schema_check_keywords(schema, key)
  assign(key, schema, envir = .schema_cache)
  schema
}

.schema_check_keywords <- function(node, where) {
  if (!is.list(node) || is.null(names(node))) {
    if (is.list(node)) lapply(node, .schema_check_keywords, where = where)
    return(invisible(TRUE))
  }
  unknown <- setdiff(names(node), .schema_keywords)
  if (length(unknown) > 0L) {
    cli::cli_abort("Schema {.file {where}} uses unsupported keyword{?s} {.val {unknown}}.")
  }
  for (k in intersect(names(node), c("properties", "definitions"))) {
    for (child in node[[k]]) .schema_check_keywords(child, where)
  }
  for (k in intersect(names(node), c("items", "additionalProperties"))) {
    if (is.list(node[[k]])) .schema_check_keywords(node[[k]], where)
  }
  for (k in intersect(names(node), c("anyOf", "oneOf"))) {
    for (child in node[[k]]) .schema_check_keywords(child, where)
  }
  invisible(TRUE)
}

# Validate a parsed JSON value (nested lists as from jsonlite with
# simplifyVector = FALSE) against a schema. Returns a character vector of
# "path: message" errors; length 0 means valid.
.schema_validate <- function(value, schema, root = schema, path = "$") {
  errors <- character()
  add <- function(msg) errors <<- c(errors, paste0(path, ": ", msg))

  if (!is.null(schema[["$ref"]])) {
    ref <- schema[["$ref"]]
    if (!startsWith(ref, "#/definitions/")) {
      return(paste0(path, ": only local #/definitions references are supported"))
    }
    target <- root$definitions[[sub("^#/definitions/", "", ref)]]
    if (is.null(target)) {
      return(paste0(path, ": unresolved reference ", ref))
    }
    return(.schema_validate(value, target, root, path))
  }

  if (!is.null(schema$type)) {
    types <- unlist(schema$type)
    if (!any(vapply(types, function(t) .json_is_type(value, t), logical(1)))) {
      add(paste0("expected type ", paste(types, collapse = "|"), ", got ", .json_type(value)))
      return(errors)
    }
  }
  if (!is.null(schema$const) && !.json_equal(value, schema$const)) {
    add(paste0("must equal ", .canonical_json(schema$const)))
  }
  if (!is.null(schema$enum) &&
      !any(vapply(schema$enum, function(e) .json_equal(value, e), logical(1)))) {
    add(paste0("must be one of ", .canonical_json(schema$enum)))
  }

  if (.json_is_type(value, "string")) {
    n <- nchar(value, type = "chars")
    if (!is.null(schema$minLength) && n < schema$minLength) add("string too short")
    if (!is.null(schema$maxLength) && n > schema$maxLength) add("string too long")
    if (!is.null(schema$pattern) && !grepl(schema$pattern, value, perl = TRUE)) {
      add(paste0("does not match pattern ", schema$pattern))
    }
  }
  if (.json_is_type(value, "number")) {
    if (!is.null(schema$minimum) && value < schema$minimum) add(paste0("below minimum ", schema$minimum))
    if (!is.null(schema$maximum) && value > schema$maximum) add(paste0("above maximum ", schema$maximum))
  }

  if (.json_is_type(value, "object")) {
    for (req in unlist(schema$required)) {
      if (!req %in% names(value)) add(paste0("missing required property '", req, "'"))
    }
    props <- schema$properties %||% list()
    for (nm in names(value)) {
      child_path <- paste0(path, ".", nm)
      if (nm %in% names(props)) {
        errors <- c(errors, .schema_validate(value[[nm]], props[[nm]], root, child_path))
      } else if (isFALSE(schema$additionalProperties)) {
        errors <- c(errors, paste0(child_path, ": unknown property (use 'extensions')"))
      } else if (is.list(schema$additionalProperties)) {
        errors <- c(errors, .schema_validate(value[[nm]], schema$additionalProperties,
                                             root, child_path))
      }
    }
  }

  if (.json_is_type(value, "array")) {
    if (!is.null(schema$minItems) && length(value) < schema$minItems) add("too few items")
    if (!is.null(schema$maxItems) && length(value) > schema$maxItems) add("too many items")
    if (is.list(schema$items)) {
      for (i in seq_along(value)) {
        errors <- c(errors, .schema_validate(value[[i]], schema$items, root,
                                             paste0(path, "[", i - 1L, "]")))
      }
    }
  }

  if (!is.null(schema$anyOf)) {
    ok <- vapply(schema$anyOf, function(s) length(.schema_validate(value, s, root, path)) == 0L,
                 logical(1))
    if (!any(ok)) add("matches none of the allowed alternatives")
  }
  if (!is.null(schema$oneOf)) {
    ok <- vapply(schema$oneOf, function(s) length(.schema_validate(value, s, root, path)) == 0L,
                 logical(1))
    if (sum(ok) != 1L) add("must match exactly one alternative")
  }
  errors
}

.json_type <- function(x) {
  if (is.null(x)) return("null")
  if (is.list(x)) return(if (!is.null(names(x))) "object" else "array")
  if (length(x) != 1L) return("array")
  if (is.logical(x)) return("boolean")
  if (is.character(x)) return("string")
  if (is.numeric(x)) return(if (is.finite(x) && x == round(x)) "integer" else "number")
  "unknown"
}

.json_is_type <- function(x, type) {
  actual <- .json_type(x)
  switch(type,
    integer = actual == "integer",
    number = actual %in% c("integer", "number"),
    actual == type
  )
}

.json_equal <- function(a, b) identical(.canonical_json(a), .canonical_json(b))

# Convert an R document to the parsed-JSON representation used for validation.
.as_json_value <- function(x) {
  txt <- jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  jsonlite::fromJSON(txt, simplifyVector = FALSE)
}

# Validate against a shipped schema and abort with a classified error.
.schema_assert <- function(value, family, name, what = name, call = rlang::caller_env()) {
  errs <- .schema_validate(value, .schema_load(family, name))
  if (length(errs) > 0L) {
    shown <- utils::head(errs, 8L)
    .at_abort(
      c("The {what} document does not satisfy {.file {family}/{name}.schema.json}.",
        stats::setNames(shown, rep("x", length(shown)))),
      code = "SCHEMA_INVALID", details = list(errors = utils::head(errs, 50L)), call = call
    )
  }
  invisible(value)
}

# Accept a document only when its major schema version matches `major`.
.check_major_version <- function(version, major, what, call = rlang::caller_env()) {
  if (!.is_string(version) || !grepl("^[0-9]+\\.[0-9]+$", version)) {
    .at_abort("The {what} version must look like {.val 1.0}.", class = "protocol",
              code = "PROTOCOL_MISMATCH", call = call)
  }
  if (as.integer(sub("\\..*$", "", version)) != major) {
    .at_abort(
      c("Unsupported {what} major version {.val {version}}.",
        "i" = "This annotatR understands major version {major}."),
      class = "protocol", code = "PROTOCOL_MISMATCH",
      details = list(received = version, supported = paste0(major, ".x")), call = call
    )
  }
  invisible(version)
}
