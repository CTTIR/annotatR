# Connect to a running control service

Build a remote handle for a control service started in another R
process, from its lifecycle manifest and token file. The handshake is
checked before the handle is returned: protocol, major version and
instance id must match the manifest.

## Usage

``` r
at_control_connect(manifest, token_file, call = rlang::caller_env())
```

## Arguments

- manifest:

  Path of the `annotatr-control-<instance_id>.json` manifest.

- token_file:

  Path of the token file passed to
  [`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md).

- call:

  The calling environment, for error reporting.

## Value

An `at_control_handle` of kind `"remote"`.

## See also

Other control:
[`at_control_capabilities()`](https://cttir.github.io/annotatR/reference/at_control_capabilities.md),
[`at_control_close()`](https://cttir.github.io/annotatR/reference/at_control_close.md),
[`at_control_command()`](https://cttir.github.io/annotatR/reference/at_control_command.md),
[`at_control_events()`](https://cttir.github.io/annotatR/reference/at_control_events.md),
[`at_control_request_status()`](https://cttir.github.io/annotatR/reference/at_control_request_status.md),
[`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md),
[`at_control_state()`](https://cttir.github.io/annotatR/reference/at_control_state.md),
[`at_control_stop()`](https://cttir.github.io/annotatR/reference/at_control_stop.md)
