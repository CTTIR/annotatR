# Control protocol capabilities

Describe the `annotatr-control-v1` protocol this annotatR version
speaks, without starting anything: endpoints, typed operations, limits,
security rules and the digests of the shipped JSON Schemas. A client
compares this (or the `/v1/handshake` response) with its own
expectations before sending commands.

## Usage

``` r
at_control_capabilities()
```

## Value

A list with `protocol`, `protocol_version`, `annotatr_version`, `status`
(see
[`at_interop_capabilities()`](https://cttir.github.io/annotatR/reference/at_interop_capabilities.md)),
`endpoints`, `operations`, `limits`, `security`, `schemas` (file name
-\> SHA-256) and `digest`.

## See also

[`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md),
[`at_control_command()`](https://cttir.github.io/annotatR/reference/at_control_command.md)

Other control:
[`at_control_close()`](https://cttir.github.io/annotatR/reference/at_control_close.md),
[`at_control_command()`](https://cttir.github.io/annotatR/reference/at_control_command.md),
[`at_control_connect()`](https://cttir.github.io/annotatR/reference/at_control_connect.md),
[`at_control_events()`](https://cttir.github.io/annotatR/reference/at_control_events.md),
[`at_control_request_status()`](https://cttir.github.io/annotatR/reference/at_control_request_status.md),
[`at_control_start()`](https://cttir.github.io/annotatR/reference/at_control_start.md),
[`at_control_state()`](https://cttir.github.io/annotatR/reference/at_control_state.md),
[`at_control_stop()`](https://cttir.github.io/annotatR/reference/at_control_stop.md)

## Examples

``` r
cc <- at_control_capabilities()
cc$operations
#> [[1]]
#> [1] "session.load"
#> 
#> [[2]]
#> [1] "session.save"
#> 
#> [[3]]
#> [1] "context.goto"
#> 
#> [[4]]
#> [1] "context.view"
#> 
#> [[5]]
#> [1] "context.selection"
#> 
#> [[6]]
#> [1] "annotations.stage"
#> 
#> [[7]]
#> [1] "annotations.commit"
#> 
#> [[8]]
#> [1] "mask.preview"
#> 
#> [[9]]
#> [1] "export"
#> 
#> [[10]]
#> [1] "training.export"
#> 
#> [[11]]
#> [1] "close"
#> 
```
