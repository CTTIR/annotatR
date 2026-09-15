# Read control events after a cursor

Read control events after a cursor

## Usage

``` r
at_control_events(
  handle,
  after = NULL,
  limit = 100L,
  call = rlang::caller_env()
)
```

## Arguments

- handle:

  An `at_control_handle`.

- after:

  Optional event cursor (`"<instance_id>:<seq>"`); `NULL` returns the
  retained buffer. A cursor from another instance or older than the
  buffer yields `resync_required = TRUE`.

- limit:

  Maximum number of events to return.

- call:

  The calling environment, for error reporting.

## Value

A list with `events`, `next_cursor`, `resync_required`, `has_more` and
`state_revision`.

## See also

Other control:
[`at_control_capabilities()`](https://cttir.github.io/annotatR/reference/at_control_capabilities.md),
[`at_control_close()`](https://cttir.github.io/annotatR/reference/at_control_close.md),
[`at_control_command()`](https://cttir.github.io/annotatR/reference/at_control_command.md),
[`at_control_connect()`](https://cttir.github.io/annotatR/reference/at_control_connect.md),
[`at_control_request_status()`](https://cttir.github.io/annotatR/reference/at_control_request_status.md),
[`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md),
[`at_control_state()`](https://cttir.github.io/annotatR/reference/at_control_state.md),
[`at_control_stop()`](https://cttir.github.io/annotatR/reference/at_control_stop.md)
