# Internal input validators. Each accepts `arg` (the caller's argument name)
# and `call` (the caller's environment) so that errors are attributed to the
# user-facing function, not to the validator. None are exported.
#
# Every validator returns its (coerced) input invisibly on success and aborts
# via `cli::cli_abort()` on failure.

# A single non-missing string.
.check_string <- function(x,
                          allow_null = FALSE,
                          arg = rlang::caller_arg(x),
                          call = rlang::caller_env()) {
  if (allow_null && is.null(x)) {
    return(invisible(x))
  }
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a single string.",
        "x" = "You supplied {.cls {class(x)[1]}} of length {length(x)}."
      ),
      call = call
    )
  }
  invisible(x)
}

# A single non-missing TRUE/FALSE.
.check_flag <- function(x,
                        arg = rlang::caller_arg(x),
                        call = rlang::caller_env()) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a single {.code TRUE} or {.code FALSE}.",
        "x" = "You supplied {.cls {class(x)[1]}} of length {length(x)}."
      ),
      call = call
    )
  }
  invisible(x)
}

# A single finite number, optionally bounded.
.check_number <- function(x,
                          min = -Inf,
                          max = Inf,
                          allow_null = FALSE,
                          arg = rlang::caller_arg(x),
                          call = rlang::caller_env()) {
  if (allow_null && is.null(x)) {
    return(invisible(x))
  }
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a single finite number.",
        "x" = "You supplied {.cls {class(x)[1]}} of length {length(x)}."
      ),
      call = call
    )
  }
  if (x < min || x > max) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be in the range [{min}, {max}].",
        "x" = "You supplied {.val {x}}."
      ),
      call = call
    )
  }
  invisible(as.numeric(x))
}

# A single non-negative whole number (a count). Returns an integer.
.check_count <- function(x,
                         min = 0L,
                         arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x != round(x)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a single whole number.",
        "x" = "You supplied {.cls {class(x)[1]}} of length {length(x)}."
      ),
      call = call
    )
  }
  xi <- as.integer(round(x))
  if (xi < min) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be at least {min}.",
        "x" = "You supplied {.val {xi}}."
      ),
      call = call
    )
  }
  invisible(xi)
}

# An existing file.
.check_file <- function(x,
                        arg = rlang::caller_arg(x),
                        call = rlang::caller_env()) {
  .check_string(x, arg = arg, call = call)
  if (!file.exists(x) || dir.exists(x)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be an existing file.",
        "x" = "{.path {x}} does not exist.",
        "i" = "Use {.fn at_example_path} to locate the bundled sample data."
      ),
      call = call
    )
  }
  invisible(x)
}

# An existing directory.
.check_dir <- function(x,
                       arg = rlang::caller_arg(x),
                       call = rlang::caller_env()) {
  .check_string(x, arg = arg, call = call)
  if (!dir.exists(x)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be an existing directory.",
        "x" = "{.path {x}} does not exist or is not a directory."
      ),
      call = call
    )
  }
  invisible(x)
}

# `x` must inherit from S3 class `cls`.
.check_class <- function(x,
                         cls,
                         allow_null = FALSE,
                         arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  if (allow_null && is.null(x)) {
    return(invisible(x))
  }
  if (!inherits(x, cls)) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a {.cls {cls}} object.",
        "x" = "You supplied {.cls {class(x)[1]}}."
      ),
      call = call
    )
  }
  invisible(x)
}

# `x` must be exactly one of `choices` (no partial matching). Returns the match.
# When `x` is the full `choices` vector (the `c(...)` default idiom), the first
# choice is returned, mirroring `match.arg()`.
.check_choice <- function(x,
                          choices,
                          arg = rlang::caller_arg(x),
                          call = rlang::caller_env()) {
  if (identical(x, choices)) {
    return(choices[[1]])
  }
  if (length(x) != 1L) {
    x <- x[[1]]
  }
  if (!is.character(x) || is.na(x) || !x %in% choices) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be one of {.or {.val {choices}}}.",
        "x" = "You supplied {.val {x}}."
      ),
      call = call
    )
  }
  x
}

# Domain-object validators.

.check_image <- function(x,
                         arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  .check_class(x, "annot_image", arg = arg, call = call)
}

.check_roi <- function(x,
                       arg = rlang::caller_arg(x),
                       call = rlang::caller_env()) {
  .check_class(x, "annot_roi", arg = arg, call = call)
}

.check_layer <- function(x,
                         arg = rlang::caller_arg(x),
                         call = rlang::caller_env()) {
  .check_class(x, "annot_layer", arg = arg, call = call)
}

.check_project <- function(x,
                           arg = rlang::caller_arg(x),
                           call = rlang::caller_env()) {
  .check_class(x, "annot_project", arg = arg, call = call)
}
