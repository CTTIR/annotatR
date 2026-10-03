import qupath.lib.io.PathIO
import qupath.lib.io.GsonTools

def objects = PathIO.readObjects(new File(args[0]))
def rows = objects.collect { o ->
  def r=o.getROI()
  [id:o.getID().toString(),label:o.getPathClass()?.toString(),color:o.getPathClass()?.getColor(),locked:o.isLocked(),objectClass:o.getClass().getSimpleName(),x:r.getBoundsX(),y:r.getBoundsY(),width:r.getBoundsWidth(),height:r.getBoundsHeight(),area:r.getArea(),wkt:r.getGeometry().toText()]
}
new File(args[1]).text=GsonTools.getInstance(true).toJson(rows)+'\n'
assert rows.size()==2
assert rows[0].label=='region'
assert rows[0].x==8 && rows[0].y==6 && rows[0].width==12 && rows[0].height==8 && rows[0].area==96
assert rows[0].locked
assert rows[1].label=='donut' && rows[1].area==84
PathIO.exportObjectsAsGeoJSON(new File(args[2]),objects)
println 'QUPath_CONSUMER_PASS'
