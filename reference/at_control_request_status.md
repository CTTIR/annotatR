# Resolve the outcome of a control request

After a lost response, ask the service what happened to a request id. An
unknown id raises `REQUEST_NOT_FOUND` and has no side effect.

## Usage

``` r
at_control_request_status(handle, request_id, call = rlang::caller_env())
```

## Arguments

- handle:

  An `at_control_handle`.

- request_id:

  The `request_id` of the earlier command.

- call:

  The calling environment, for error reporting.

## Value

The request record: `request_id`, `operation`, `status` (`"completed"`
or `"failed"`), `http_status`, timestamps, `extensions` and the stored
`response`.

## See also

Other control:
[`at_control_capabilities()`](https://cttir.github.io/annotatR/reference/at_control_capabilities.md),
[`at_control_close()`](https://cttir.github.io/annotatR/reference/at_control_close.md),
[`at_control_command()`](https://cttir.github.io/annotatR/reference/at_control_command.md),
[`at_control_connect()`](https://cttir.github.io/annotatR/reference/at_control_connect.md),
[`at_control_events()`](https://cttir.github.io/annotatR/reference/at_control_events.md),
[`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md),
[`at_control_state()`](https://cttir.github.io/annotatR/reference/at_control_state.md),
[`at_control_stop()`](https://cttir.github.io/annotatR/reference/at_control_stop.md)
