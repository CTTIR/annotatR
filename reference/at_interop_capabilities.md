# Partner interoperability capabilities

Report what this annotatR installation can exchange with a partner
package such as qupflowR, and how far each capability has been
qualified. Profiles follow the partner contract: I0 file interchange, I1
public R API, I2 the local control service (`annotatr-control-v1`) and
I3 the embeddable app object from
[`at_app()`](https://cttir.github.io/annotatR/reference/at_app.md). A
profile is `"supported"` only with implementation, runtime dependencies
and qualification evidence; implemented profiles that have not passed
their tests against a real partner client are `"planned"`; profiles
whose optional runtime is missing are `"unavailable"`. Every entry
carries a `reason` when it is not supported.

## Usage

``` r
at_interop_capabilities(
  target = c("package", "hsi", "app", "control"),
  call = rlang::caller_env()
)
```

## Arguments

- target:

  One or more of `"package"`, `"hsi"`, `"app"`, `"control"`.

- call:

  The calling environment, for error reporting.

## Value

A list of class `at_capabilities` with `schema`, `schema_version`,
`annotatr_version`, `r_version`, `source_revision`, `consumer`,
`profiles` (I0-I3), `limits`, and the requested sections `package`,
`hsi`, `app`, `control`, plus `digest`: the SHA-256 of the canonical
JSON of the report without `digest` itself.

## See also

[`at_interop_manifest()`](https://cttir.github.io/annotatR/reference/at_interop_manifest.md),
[`at_control_capabilities()`](https://cttir.github.io/annotatR/reference/at_control_capabilities.md)

Other interop:
[`at_annotation_revision()`](https://cttir.github.io/annotatR/reference/at_annotation_revision.md),
[`at_commit_qupflowr()`](https://cttir.github.io/annotatR/reference/at_commit_qupflowr.md),
[`at_export_qupflowr()`](https://cttir.github.io/annotatR/reference/at_export_qupflowr.md),
[`at_import_qupflowr()`](https://cttir.github.io/annotatR/reference/at_import_qupflowr.md),
[`at_interop_manifest()`](https://cttir.github.io/annotatR/reference/at_interop_manifest.md),
[`at_stage_qupflowr()`](https://cttir.github.io/annotatR/reference/at_stage_qupflowr.md)

## Examples

``` r
caps <- at_interop_capabilities()
caps$profiles$I0$status
#> [1] "supported"
caps$digest
#> [1] "d279f3d2d735190e25c37b8a9d6e5d4ca76ee00854c3fa8984c8f86fa85af500"
```
