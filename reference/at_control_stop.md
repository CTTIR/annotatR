# Stop a local control service

Stop a service started by
[`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md)
in this R process: close the listener, invalidate its token and rewrite
its lifecycle manifest as stopped. A handle from another process (or a
remote handle from
[`at_control_connect()`](https://cttir.github.io/annotatR/reference/at_control_connect.md))
is refused with an `at_auth_error` (`NOT_OWNER`); no process is ever
terminated.

## Usage

``` r
at_control_stop(handle, call = rlang::caller_env())
```

## Arguments

- handle:

  An `at_control_handle` of kind `"local"`.

- call:

  The calling environment, for error reporting.

## Value

`TRUE` invisibly when the service was stopped, `FALSE` if it had already
stopped.

## See also

Other control:
[`at_control_capabilities()`](https://cttir.github.io/annotatR/reference/at_control_capabilities.md),
[`at_control_close()`](https://cttir.github.io/annotatR/reference/at_control_close.md),
[`at_control_command()`](https://cttir.github.io/annotatR/reference/at_control_command.md),
[`at_control_connect()`](https://cttir.github.io/annotatR/reference/at_control_connect.md),
[`at_control_events()`](https://cttir.github.io/annotatR/reference/at_control_events.md),
[`at_control_request_status()`](https://cttir.github.io/annotatR/reference/at_control_request_status.md),
[`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md),
[`at_control_state()`](https://cttir.github.io/annotatR/reference/at_control_state.md)
