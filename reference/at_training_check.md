# Check a training dataset

Run independent checks on an exported training dataset: the integrity
inventory, split leakage (every group and image in exactly one split,
every tile in its image's split), mask dimensions and orientation,
integer label range against the class legend, the recorded overlap
counts, and a mask -\> ROI -\> mask round trip on a sample of tiles.
When the source `x` is supplied, each sampled tile is also re-rasterised
from the annotations and compared exactly.

## Usage

``` r
at_training_check(
  dataset,
  x = NULL,
  max_roundtrip_tiles = 20L,
  call = rlang::caller_env()
)
```

## Arguments

- dataset:

  Path of a dataset written by
  [`at_training_export()`](https://cttir.github.io/annotatR/reference/at_training_export.md).

- x:

  Optional source
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
  or
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- max_roundtrip_tiles:

  Maximum number of tiles sampled for round trips.

- call:

  The calling environment, for error reporting.

## Value

A tibble of class `at_training_check` with `check`, `status` (`"ok"`,
`"warn"`, `"fail"`) and `detail`.

## See also

Other training:
[`at_training_export()`](https://cttir.github.io/annotatR/reference/at_training_export.md),
[`at_training_import()`](https://cttir.github.io/annotatR/reference/at_training_import.md)
