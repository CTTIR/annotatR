img <- magick::image_read('/tmp/annotatr-roadmap-mask-pgm-probe/reference.pgm')
magick::image_write(img, '/tmp/annotatr-roadmap-mask-pgm-probe/reference.tif', format='tiff',depth=16L,compression='none')
magick::image_write(img, '/tmp/annotatr-roadmap-mask-pgm-probe/reference.png', format='png',depth=16L)
