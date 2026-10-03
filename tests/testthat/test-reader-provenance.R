reader_contract_mask <- function(backend='ometiff', contract=list(axes='yxb',samples='raw-scalar-v1')) {
  m <- .mask_recover(matrix(c(1,0,0,1),2,2))
  attr(m,'mask_metadata')$source <- list(descriptor=list(schema_version=1L,
    path='/synthetic/square.ome.tif',backend=backend,options=list(),signature=list(size=100,mtime=10),
    reader_contract=contract))
  m
}
test_that('square-image mask alignment checks durable pixel/axis semantics', {
  a <- reader_contract_mask()
  for (contract in list(NULL,list(axes='xyb',samples='raw-scalar-v1'),list(axes='yxb',samples='display-scaled'))) {
    b <- reader_contract_mask(contract=contract)
    expect_error(at_mask_derive(a,b,keep_label='1'),'contract|unverified|conflict')
    expect_no_error(at_mask_derive(a,b,keep_label='1',alignment='assert'))
  }
  expect_no_error(at_mask_derive(a,a,keep_label='1'))
  old <- reader_contract_mask(contract=NULL)
  another <- old;attr(another,'mask_metadata')$source$entry_id<-'different-entry'
  expect_error(at_mask_derive(old,another,keep_label='1'),'contract|unverified')
  custom <- reader_contract_mask('custom',NULL)
  legacy_custom <- custom
  attr(legacy_custom,'mask_metadata')$source$descriptor$reader_contract <- NULL
  attr(legacy_custom,'mask_metadata')$source$entry_id <- 'other-entry'
  expect_no_error(at_mask_derive(custom,legacy_custom,keep_label='1'))
})
test_that('raw reader contracts survive image and mask persistence', {
  skip_if_not_installed('tiff')
  img <- at_read_image(test_path('fixtures','readers','images','reference-uint16.tif'),backend='tiff')
  expect_identical(img$source_descriptor$reader_contract,list(axes='yxb',samples='raw-scalar-v1'))
  m <- at_mask(at_roi_rect(0,0,1,1,label='1'),'multiclass',dims=img$dims,image=img)
  expect_identical(attr(m,'mask_metadata')$source$descriptor$reader_contract,img$meta$reader_contract)
  p <- tempfile(fileext='.npy');withr::defer(unlink(c(p,paste0(p,'.legend.json'))))
  at_write_npy(m,p);back<-at_read_npy(p)
  expect_identical(attr(back,'mask_metadata')$source$descriptor$reader_contract,img$meta$reader_contract)
  expect_no_error(at_mask_derive(m,back,keep_label='1'))
})
