# Export a DNN training dataset

Tile annotated images into a portable training dataset with integer
masks, deterministic grouped splits and a complete provenance manifest.
Splits are assigned per group (by default per image, or by
`subject_id`/`sample_id` from `groups`), so tiles of one group never
occur in two splits. Masks are written as integer TIFF (or NPY) with
background `0`; class codes are shared across the dataset and instance
ids are only produced for `mask_type = "instance"`. Tiles that do not
fit the image are excluded as partial; empty and ambiguous (overlapping
labels) tiles are counted and handled by policy. Image bytes are
excluded unless `include_images = TRUE`.

## Usage

``` r
at_training_export(
  x,
  destination,
  split = NULL,
  tile_size = 256L,
  overlap = 0L,
  level = 0L,
  mask_type = c("labelled", "instance", "binary"),
  bands = NULL,
  include_images = FALSE,
  seed = 1L,
  group_by = c("image_id", "sample_id", "subject_id"),
  groups = NULL,
  fractions = c(train = 0.7, validation = 0.15, test = 0.15),
  label_map = NULL,
  empty_tiles = c("keep", "exclude"),
  mask_format = c("tiff", "npy"),
  normalization = NULL,
  overwrite = FALSE,
  call = rlang::caller_env()
)
```

## Arguments

- x:

  An
  [annot_session](https://cttir.github.io/annotatR/reference/annotatR-classes.md)
  (materialised entries) or
  [annot_project](https://cttir.github.io/annotatR/reference/annotatR-classes.md).

- destination:

  New dataset directory.

- split:

  Optional explicit assignment: a named list (`train`, `validation`,
  `test`) of group ids. `NULL` assigns groups by `fractions` and `seed`.

- tile_size:

  Tile edge length in pixels at `level`.

- overlap:

  Tile overlap in pixels (`0 <= overlap < tile_size`).

- level:

  Pyramid level.

- mask_type:

  `"labelled"`, `"instance"` or `"binary"`.

- bands:

  Band indices recorded (and written with `include_images`).

- include_images:

  Logical; also write float32 NPY image tiles.

- seed:

  Split seed (recorded).

- group_by:

  Group column used for splitting: `"image_id"` (default), `"sample_id"`
  or `"subject_id"`.

- groups:

  Optional data frame with `entry_id` (or `name`) plus `subject_id`
  and/or `sample_id` columns (character).

- fractions:

  Named split fractions.

- label_map:

  Optional named integer class codes (`label = code`, codes `>= 1`);
  defaults to first-seen label order.

- empty_tiles:

  `"keep"` (default) or `"exclude"` tiles without foreground.

- mask_format:

  `"tiff"` (default) or `"npy"`.

- normalization:

  Optional list describing value normalisation applied downstream
  (recorded, not applied).

- overwrite:

  Logical; replace an existing dataset directory.

- call:

  The calling environment, for error reporting.

## Value

An `at_training_export` list: `destination`, `dataset_digest`,
`manifest`, `files` and `checks` (from
[`at_training_check()`](https://cttir.github.io/annotatR/reference/at_training_check.md)).

## Details

`mask_type` uses training terminology: `"labelled"` is a semantic
class-code mask (annotatR `"multiclass"`), `"instance"` has one id per
ROI (annotatR `"labelled"`), `"binary"` marks foreground. The mapping is
recorded in the manifest.

## See also

[`at_training_check()`](https://cttir.github.io/annotatR/reference/at_training_check.md),
[`at_training_import()`](https://cttir.github.io/annotatR/reference/at_training_import.md)

Other training:
[`at_training_check()`](https://cttir.github.io/annotatR/reference/at_training_check.md),
[`at_training_import()`](https://cttir.github.io/annotatR/reference/at_training_import.md)

## Examples

``` r
sess <- at_example_session(3)
for (i in 1:3) sess$projects[[i]] <- at_example_project()
ds <- at_training_export(sess, file.path(tempdir(), "train-example"), tile_size = 128,
                         overwrite = TRUE)
ds$manifest$counts$tiles
#> [1] 48
```
