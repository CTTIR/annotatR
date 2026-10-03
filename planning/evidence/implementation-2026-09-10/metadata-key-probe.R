pkgload::load_all()
m <- .mask_recover(matrix(c(1,0,0,1),2,2))
attr(m,'mask_metadata')$source <- list(descriptor=list(schema_version=1L,
 path='/synthetic/square.ome.tif',backend='ometiff',options=list(),
 signature=list(size=100,mtime=10),reader_contract=list(axes='yxb',samples='raw-scalar-v1')))
other <- m
names(attr(other,'mask_metadata')$source$descriptor)[names(attr(other,'mask_metadata')$source$descriptor)=='reader_contract'] <- 'reader_contract_extra'
attr(other,'mask_metadata')$source$entry_id <- 'different-entry'
result <- tryCatch(at_mask_derive(m,other,keep_label='1'),error=function(e)e)
observed <- list(supplied_descriptor_keys=names(attr(other,'mask_metadata')$source$descriptor),
 expected='unverified reader-contract error: exact reader_contract is absent',
 imported= !inherits(result,'error'),
 result=if(inherits(result,'error'))conditionMessage(result) else attr(result,'mask_metadata'))
jsonlite::write_json(observed,'/tmp/annotatr-roadmap-metadata-key-probe/observed.json',pretty=TRUE,auto_unbox=TRUE,digits=NA,null='null')
print(observed)
p <- '/tmp/annotatr-roadmap-metadata-key-probe/prefix.npy'
at_write_npy(other,p,overwrite=TRUE)
back <- at_read_npy(p)
from_file <- tryCatch(at_mask_derive(m,back,keep_label='1'),error=function(e)e)
observed$npy_roundtrip <- list(descriptor_keys=names(attr(back,'mask_metadata')$source$descriptor),
 accepted=!inherits(from_file,'error'),
 alignment=if(inherits(from_file,'error'))conditionMessage(from_file) else attr(from_file,'mask_metadata')$derivation$anatomy_alignment)
jsonlite::write_json(observed,'/tmp/annotatr-roadmap-metadata-key-probe/observed.json',pretty=TRUE,auto_unbox=TRUE,digits=NA,null='null')
print(observed$npy_roundtrip)
