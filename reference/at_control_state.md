# Read the state of a control service

Read the state of a control service

## Usage

``` r
at_control_state(handle, call = rlang::caller_env())
```

## Arguments

- handle:

  An `at_control_handle`.

- call:

  The calling environment, for error reporting.

## Value

The state snapshot (a list) with `state_revision`, `event_cursor`,
`queue`, `current` (image, layers, ROI summaries, annotation revision),
`view`, `selection`, `staged`, `last_commit` and status fields.

## See also

Other control:
[`at_control_capabilities()`](https://cttir.github.io/annotatR/reference/at_control_capabilities.md),
[`at_control_close()`](https://cttir.github.io/annotatR/reference/at_control_close.md),
[`at_control_command()`](https://cttir.github.io/annotatR/reference/at_control_command.md),
[`at_control_connect()`](https://cttir.github.io/annotatR/reference/at_control_connect.md),
[`at_control_events()`](https://cttir.github.io/annotatR/reference/at_control_events.md),
[`at_control_request_status()`](https://cttir.github.io/annotatR/reference/at_control_request_status.md),
[`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md),
[`at_control_stop()`](https://cttir.github.io/annotatR/reference/at_control_stop.md)
