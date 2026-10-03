# Native TIFF callback diagnosis

This evidence isolates the T07/T13 native abort on the local R4.6.1, tiff0.1.12, magick2.9.1 / ImageMagick7.1.2.18 configuration. The script calls only dependency APIs and reads the bundled multiplex TIFF; it does not load annotatR or Java.

Run from the implementation checkout with a separate process and core dumps disabled for that process. The exact R invocation is `Rscript --vanilla planning/evidence/implementation-2026-09-10/native-diagnostic/tiff-handler-order.R MODE`, where MODE is one of the three recorded cases:

| Mode | Observed child result | Meaning |
|---|---|---|
| tiff-only | Exit0; three ExtraSamples warnings; TIFF returned | Control reads the same fixture without ImageMagick TIFF initialization |
| retained | SIGABRT; Python return code -6 | Tiny R-tiff write, ImageMagick TIFF read, then R-tiff read of warning-producing fixture |
| destroy | SIGABRT; Python return code -6 | Same sequence, after removing the magick image and running GC |

The Python launcher used `subprocess.run` with stdout/stderr redirected to the matching log, timeout60s, and child-only `resource.setrlimit(resource.RLIMIT_CORE, (0, 0))`. No global process or dependency settings changed. Shells commonly report SIGABRT as exit134.

`backtrace.log` captures the retained case using gdb batch commands `set pagination off`, `run`, and `bt 32`, with the R executable at the current `R RHOME` plus `/bin/exec/R` and arguments `--vanilla --no-save --file=SCRIPT --args retained`. The child environment sets R_HOME to that same R installation. The gdb command exits0 after capturing the fatal signal; this is a failing native case, not a passing qualification.

The stack reaches `TIFFWarningExtR` from R tiff's `TIFF_Open`/`TIFFReadDirectory`, then enters the ImageMagick TIFF coder and `ThrowMagickException`, which asserts an invalid exception signature. The [matching upstream TIFF coder](https://github.com/ImageMagick/ImageMagick/blob/7.1.2-18/coders/tiff.c) registers global TIFF callbacks and uses a thread-local exception pointer. Together these establish a cross-library callback failure on this configuration. They do not establish a Java or thread-count cause, a universal version range, or a completed mitigation. T18a owns the package correction and its qualification; historical failure logs remain unchanged.

Additional native controls: tiff-handler-non-tiff.R initializes R tiff, then either magick PNG reading or array reading plus PNG encoding, then reads the same warning-producing multiplex TIFF. Both fresh subprocesses exit0 with the expected three TIFF warnings (png.log/array.log); no abort. This supports scoping the mitigation to TIFF codec interactions on this host, but is not proof that arbitrary native formats or global initialization orders are safe.
