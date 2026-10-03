pkgload::load_all('/tmp/annotatr-roadmap-baseline-source', quiet=TRUE)
for (tag in c('le','be')) {
  img <- at_read_image(file.path('/tmp/annotatr-roadmap-envi-int32-probe',paste0(tag,'.dat')),backend='envi')
  cat(tag, ': '); dput(as.vector(at_tile(img)))
}
