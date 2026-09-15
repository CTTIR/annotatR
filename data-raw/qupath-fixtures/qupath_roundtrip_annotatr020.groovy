/**
 * READ + RE-EXPORT TEST for annotatR's QuPath dialect (annotatr_020_qupath_dialect.geojson).
 *
 * (1) PathIO.readObjects() the annotatR file and describe each object in file order.
 * (2) Re-export the objects with PathIO.exportObjectsAsGeoJSON(FEATURE_COLLECTION) to
 *     qupath_roundtrip_annotatr020.geojson, then parse that export (plain Gson) and the
 *     input (plain Gson) to check whether feature ids and properties.metadata survived.
 *
 * Run from the directory containing the input:
 *   java -Djava.awt.headless=true --enable-native-access=ALL-UNNAMED \
 *     -cp "/opt/QuPath-v0.7.0/lib/app/*" qupath.QuPath script qupath_roundtrip_annotatr020.groovy
 *
 * Output: qupath_reads_annotatr020.json, qupath_roundtrip_annotatr020.geojson
 */
import ch.qos.logback.classic.Logger
import ch.qos.logback.classic.spi.ILoggingEvent
import ch.qos.logback.core.read.ListAppender
import com.google.gson.GsonBuilder
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import org.locationtech.jts.geom.Polygon
import org.slf4j.LoggerFactory
import qupath.lib.common.ColorTools
import qupath.lib.common.GeneralTools
import qupath.lib.io.PathIO

def baseDir = new File(System.getProperty("user.dir"))
def inFile = new File(baseDir, "annotatr_020_qupath_dialect.geojson")
def exportFile = new File(baseDir, "qupath_roundtrip_annotatr020.geojson")
def outFile = new File(baseDir, "qupath_reads_annotatr020.json")

def rootLogger = (Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)
def appender = new ListAppender<ILoggingEvent>()
appender.setContext(rootLogger.getLoggerContext())
appender.start()
rootLogger.addAppender(appender)

def gsonPlain = new com.google.gson.Gson()
def jsonToJava = { JsonElement e -> e == null || e.isJsonNull() ? null : gsonPlain.fromJson(e, Object) }

// Parse a GeoJSON FeatureCollection (or bare array) with plain Gson: id + properties.metadata per feature
def featureSummary = { File f ->
    def out = []
    f.withReader("UTF-8") { r ->
        def root = JsonParser.parseReader(r)
        def feats = root.isJsonArray() ? root.getAsJsonArray() : root.getAsJsonObject().getAsJsonArray("features")
        feats.each { fe ->
            def o = fe.getAsJsonObject()
            def props = o.has("properties") ? o.getAsJsonObject("properties") : new JsonObject()
            out << [id: o.has("id") && !o.get("id").isJsonNull() ? o.get("id").getAsString() : null,
                    metadata: props.has("metadata") ? jsonToJava(props.get("metadata")) : null,
                    property_keys: props.keySet().toList(),
                    geometry_keys: o.has("geometry") ? o.getAsJsonObject("geometry").keySet().toList() : null,
                    classification: props.has("classification") ? jsonToJava(props.get("classification")) : null]
        }
    }
    out
}

// Streaming scan for duplicate member names (a tree parser such as Gson's JsonParser keeps
// only one value per name and would hide duplicates). Returns [[path, name, count], ...].
def duplicateKeys = { File f ->
    def dups = []
    def reader = new com.google.gson.stream.JsonReader(new InputStreamReader(new FileInputStream(f), "UTF-8"))
    def scan
    scan = { String path ->
        switch (reader.peek()) {
            case com.google.gson.stream.JsonToken.BEGIN_OBJECT:
                reader.beginObject()
                def counts = new LinkedHashMap<String, Integer>()
                while (reader.hasNext()) {
                    def name = reader.nextName()
                    counts.put(name, (counts.get(name) ?: 0) + 1)  // not counts[name]: Groovy maps special-case "properties"/"class"
                    scan.call(path + "." + name)
                }
                reader.endObject()
                counts.each { k, v -> if (v > 1) dups << [path: path, name: k, count: v] }
                break
            case com.google.gson.stream.JsonToken.BEGIN_ARRAY:
                reader.beginArray()
                int i = 0
                while (reader.hasNext()) { scan.call(path + "[" + (i++) + "]") }
                reader.endArray()
                break
            default:
                reader.skipValue()
        }
    }
    try { scan.call("\$") } finally { reader.close() }
    dups
}

def rgb = { Integer packed ->
    packed == null ? null : [r: ColorTools.red(packed), g: ColorTools.green(packed), b: ColorTools.blue(packed), packed_signed_int: packed]
}

def result = new LinkedHashMap()
result.qupath_version = GeneralTools.getVersion()
result.java_version = System.getProperty("java.version")
result.input_file = inFile.getName()
result.reader = "qupath.lib.io.PathIO.readObjects(java.io.File)"
def inputFeatures = featureSummary(inFile)
result.input_features_parsed_with_gson = inputFeatures

def exceptions = []
def logMark = { -> appender.list.size() }
List pathObjects = []
try {
    pathObjects = PathIO.readObjects(inFile)
} catch (Throwable t) {
    def sw = new StringWriter(); t.printStackTrace(new PrintWriter(sw))
    exceptions << [stage: "PathIO.readObjects", type: t.getClass().getName(), message: t.getMessage(), stacktrace: sw.toString()]
}
def nLogAfterRead = logMark()
result.n_objects_read = pathObjects.size()

def objectsOut = []
pathObjects.eachWithIndex { po, idx ->
    def m = new LinkedHashMap()
    try {
        m.index = idx
        m.object_class = po.getClass().getName()
        m.object_type = po.isCell() ? "cell" : (po.isTile() ? "tile" : (po.isDetection() ? "detection" : (po.isAnnotation() ? "annotation" : "other")))
        def pc = po.getPathClass()
        m.classification = pc == null ? null : [
                to_string: pc.toString(),
                name: pc.getName(),
                is_derived: pc.isDerivedClass(),
                parent: pc.getParentClass()?.toString(),
                base: pc.getBaseClass()?.toString(),
                components: pc.toSet().toList(),
                colour: rgb(pc.getColor())]
        m.object_colour = rgb(po.getColor())
        m.name = po.getName()
        m.is_locked = po.isLocked()
        def roi = po.getROI()
        m.roi_name = roi.getRoiName()
        m.roi_type = roi.getRoiType().toString()
        m.area_px = roi.getArea()
        m.length_px = roi.getLength()
        m.bounds = [x: roi.getBoundsX(), y: roi.getBoundsY(), w: roi.getBoundsWidth(), h: roi.getBoundsHeight()]
        def g = roi.getGeometry()
        int holes = 0
        for (int i = 0; i < g.getNumGeometries(); i++) {
            def gi = g.getGeometryN(i)
            if (gi instanceof Polygon) holes += ((Polygon) gi).getNumInteriorRing()
        }
        m.geometry_type = g.getGeometryType()
        m.n_interior_rings = holes
        m.plane = [c: roi.getC(), z: roi.getZ(), t: roi.getT()]
        m.id = po.getID()?.toString()
        def inId = idx < inputFeatures.size() ? inputFeatures[idx].id : null
        m.input_feature_id = inId
        m.id_equals_input = (inId != null && m.id == inId)
        m.has_metadata = po.hasMetadata()
        m.metadata = new LinkedHashMap(po.getMetadata())
        def inMeta = idx < inputFeatures.size() ? inputFeatures[idx].metadata : null
        m.input_metadata = inMeta
        m.metadata_equals_input = (inMeta != null && new LinkedHashMap(inMeta) == m.metadata)
        m.measurements = new LinkedHashMap(po.getMeasurements())
    } catch (Throwable t) {
        exceptions << [stage: "describe object " + idx, type: t.getClass().getName(), message: t.getMessage()]
    }
    objectsOut << m
}
result.objects = objectsOut

// ---- re-export -------------------------------------------------------------------
result.export = [file: exportFile.getName(), call: "PathIO.exportObjectsAsGeoJSON(File, objects, FEATURE_COLLECTION)"]
try {
    PathIO.exportObjectsAsGeoJSON(exportFile, pathObjects, PathIO.GeoJsonExportOptions.FEATURE_COLLECTION)
    result.export.bytes = exportFile.length()
    def exported = featureSummary(exportFile)
    result.export.duplicate_member_names_in_export = duplicateKeys(exportFile)
    result.export.duplicate_member_names_in_input = duplicateKeys(inFile)
    result.export.note_on_parsing = "features_parsed_with_gson/comparison use Gson's tree parser, which keeps a single value per member name; see duplicate_member_names_in_export for repeated keys"
    result.export.features_parsed_with_gson = exported
    result.export.comparison = inputFeatures.withIndex().collect { inp, i ->
        def ex = i < exported.size() ? exported[i] : null
        [index: i,
         input_id: inp.id,
         exported_id: ex?.id,
         id_survived: ex != null && ex.id == inp.id,
         input_metadata: inp.metadata,
         exported_metadata: ex?.metadata,
         metadata_survived: ex != null && inp.metadata != null && ex.metadata == inp.metadata,
         input_classification: inp.classification,
         exported_classification: ex?.classification]
    }
} catch (Throwable t) {
    def sw = new StringWriter(); t.printStackTrace(new PrintWriter(sw))
    exceptions << [stage: "PathIO.exportObjectsAsGeoJSON", type: t.getClass().getName(), message: t.getMessage(), stacktrace: sw.toString()]
}

result.exceptions = exceptions
rootLogger.detachAppender(appender)
appender.stop()
def events = appender.list.withIndex().collect { e, i ->
    [phase: i < nLogAfterRead ? "read" : "describe/export", level: e.getLevel().toString(), logger: e.getLoggerName(), message: e.getFormattedMessage(),
     throwable: e.getThrowableProxy() == null ? null : (e.getThrowableProxy().getClassName() + ": " + e.getThrowableProxy().getMessage())]
}
result.log_events = events
result.warnings_or_errors = events.findAll { it.level in ["WARN", "ERROR"] }

def gson = new GsonBuilder().setPrettyPrinting().serializeNulls().serializeSpecialFloatingPointValues().disableHtmlEscaping().create()
outFile.withWriter("UTF-8") { it.write(gson.toJson(result)); it.write("\n") }
println "Wrote ${outFile.getName()}: ${pathObjects.size()} objects, ${exceptions.size()} exceptions, ${result.warnings_or_errors.size()} warnings/errors"
println "ids equal input: " + objectsOut.collect { it.id_equals_input }
println "metadata equal input (after read): " + objectsOut.collect { it.metadata_equals_input }
println "re-export id survived: " + result.export.comparison?.collect { it.id_survived }
println "re-export metadata survived: " + result.export.comparison?.collect { it.metadata_survived }
println "duplicate member names in export: " + result.export.duplicate_member_names_in_export
