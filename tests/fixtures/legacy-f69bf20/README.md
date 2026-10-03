These synthetic files were written by untouched annotatR runtime commit
f69bf201f651c845ab496f76e25638bc919d4b13. `generate.R` records the generator,
`generation.log` its output, and `sha256.txt` the original file hashes. The only
process-local controls were a fixed clock and the annotation-author option.
No runtime source was modified. Two complete generations were byte identical.

The original absolute source path is `/tmp/annotatr-roadmap-legacy/source.tif`.
The migration test explicitly rebases that path to a temporary copy and records
both paths in test-only metadata before exercising the loader. Checked-in RDS
files retain their original bytes. The repeated-source session has distinct
first/second annotations; the memory project retains its only literal pixels.
To reproduce, check out the recorded commit at the baseline path shown in the
generator, install its dependencies and run the generator. Its output directory
must exist. No private fixtures are required.
