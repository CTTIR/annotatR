/**
 * READ TEST: let QuPath 0.7.0 read an annotatR-written QuPath-dialect GeoJSON
 * and describe, per object in file order, what QuPath made of it.
 *
 * Run from the directory containing annotatr_written_qupath.geojson:
 *   java -Djava.awt.headless=true --enable-native-access=ALL-UNNAMED \
 *     -cp "/opt/QuPath-v0.7.0/lib/app/*" qupath.QuPath script qupath_read_test.groovy
 *
 * Output: qupath_reads_annotatr.json
 */
import ch.qos.logback.classic.Logger
import ch.qos.logback.classic.spi.ILoggingEvent
import ch.qos.logback.core.read.ListAppender
import com.google.gson.GsonBuilder
import com.google.gson.JsonParser
import org.locationtech.jts.geom.Geometry
import org.locationtech.jts.geom.Polygon
import org.slf4j.LoggerFactory
import qupath.lib.common.ColorTools
import qupath.lib.common.GeneralTools
import qupath.lib.io.PathIO

def baseDir = new File(System.getProperty("user.dir"))
def inFile = new File(baseDir, "annotatr_written_qupath.geojson")
def outFile = new File(baseDir, "qupath_reads_annotatr.json")

// Capture every log event emitted while QuPath parses the file
def rootLogger = (Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)
def appender = new ListAppender<ILoggingEvent>()
appender.setContext(rootLogger.getLoggerContext())
appender.start()
rootLogger.addAppender(appender)

// Feature ids as written in the input file (independent of QuPath's parser)
def inputIds = []
inFile.withReader("UTF-8") { r ->
    def root = JsonParser.parseReader(r).getAsJsonObject()
    root.getAsJsonArray("features").each { f ->
        def o = f.getAsJsonObject()
        inputIds << (o.has("id") && !o.get("id").isJsonNull() ? o.get("id").getAsString() : null)
    }
}

def rgb = { Integer packed ->
    if (packed == null) return null
    [r: ColorTools.red(packed), g: ColorTools.green(packed), b: ColorTools.blue(packed), packed: packed]
}

def ringInfo = { Geometry g ->
    int nPolys = 0
    int nHoles = 0
    for (int i = 0; i < g.getNumGeometries(); i++) {
        def gi = g.getGeometryN(i)
        if (gi instanceof Polygon) {
            nPolys++
            nHoles += ((Polygon) gi).getNumInteriorRing()
        }
    }
    [geometry_type: g.getGeometryType(), n_geometries: g.getNumGeometries(),
     n_polygons: nPolys, n_interior_rings: nHoles, n_coordinates: g.getNumPoints()]
}

def ringsAsCoords = { Geometry g ->
    // Coordinates of each ring as held by QuPath's JTS geometry (shell first, then holes)
    def out = []
    for (int i = 0; i < g.getNumGeometries(); i++) {
        def gi = g.getGeometryN(i)
        if (gi instanceof Polygon) {
            def p = (Polygon) gi
            def rings = [p.getExteriorRing().getCoordinates().collect { [it.x, it.y] }]
            for (int h = 0; h < p.getNumInteriorRing(); h++)
                rings << p.getInteriorRingN(h).getCoordinates().collect { [it.x, it.y] }
            out << rings
        } else {
            out << gi.getCoordinates().collect { [it.x, it.y] }
        }
    }
    out
}

def result = new LinkedHashMap()
result.qupath_version = GeneralTools.getVersion()
result.java_version = System.getProperty("java.version")
result.input_file = inFile.getName()
result.input_feature_ids = inputIds
result.reader = "qupath.lib.io.PathIO.readObjects(java.io.File)"

def objectsOut = []
def exceptions = []
List pathObjects = []
try {
    pathObjects = PathIO.readObjects(inFile)
} catch (Throwable t) {
    def sw = new StringWriter()
    t.printStackTrace(new PrintWriter(sw))
    exceptions << [stage: "PathIO.readObjects", type: t.getClass().getName(), message: t.getMessage(), stacktrace: sw.toString()]
}
result.n_objects_read = pathObjects.size()

pathObjects.eachWithIndex { po, idx ->
    def m = new LinkedHashMap()
    try {
        m.index = idx
        m.object_class = po.getClass().getName()
        m.object_type = po.isCell() ? "cell" : (po.isTile() ? "tile" : (po.isDetection() ? "detection" : (po.isAnnotation() ? "annotation" : (po.isTMACore() ? "tma_core" : "other"))))
        m.is_annotation = po.isAnnotation()
        m.is_detection = po.isDetection()
        m.is_cell = po.isCell()
        def pc = po.getPathClass()
        m.classification_name = pc == null ? null : pc.toString()
        m.classification_colour = pc == null ? null : rgb(pc.getColor())
        m.object_colour = rgb(po.getColor())
        m.name = po.getName()
        m.is_locked = po.isLocked()
        def roi = po.getROI()
        m.roi_name = roi.getRoiName()
        m.roi_type = roi.getRoiType().toString()
        m.roi_class = roi.getClass().getName()
        m.area_px = roi.getArea()
        m.length_px = roi.getLength()
        m.bounds = [x: roi.getBoundsX(), y: roi.getBoundsY(), w: roi.getBoundsWidth(), h: roi.getBoundsHeight()]
        def geom = roi.getGeometry()
        m.geometry = ringInfo(geom)
        m.coordinates = ringsAsCoords(geom)
        m.plane = [c: roi.getC(), z: roi.getZ(), t: roi.getT()]
        m.id = po.getID()?.toString()
        def inId = idx < inputIds.size() ? inputIds[idx] : null
        m.input_feature_id = inId
        m.id_equals_input = (inId != null && m.id == inId)
        m.measurements = new LinkedHashMap(po.getMeasurements())
        m.metadata = new LinkedHashMap(po.getMetadata())
        if (po.isCell()) {
            def nuc = po.getNucleusROI()
            m.nucleus_roi_name = nuc == null ? null : nuc.getRoiName()
        }
    } catch (Throwable t) {
        exceptions << [stage: "describe object " + idx, type: t.getClass().getName(), message: t.getMessage()]
    }
    objectsOut << m
}
result.objects = objectsOut
result.exceptions = exceptions

rootLogger.detachAppender(appender)
appender.stop()
result.log_events = appender.list.collect { e ->
    [level: e.getLevel().toString(), logger: e.getLoggerName(), message: e.getFormattedMessage(),
     throwable: e.getThrowableProxy() == null ? null : (e.getThrowableProxy().getClassName() + ": " + e.getThrowableProxy().getMessage())]
}
result.warnings_or_errors = result.log_events.findAll { it.level in ["WARN", "ERROR"] }

def gson = new GsonBuilder().setPrettyPrinting().serializeNulls().serializeSpecialFloatingPointValues().disableHtmlEscaping().create()
outFile.withWriter("UTF-8") { it.write(gson.toJson(result)); it.write("\n") }
println "Wrote " + outFile.getAbsolutePath() + " (" + pathObjects.size() + " objects, " + exceptions.size() + " exceptions, " + result.warnings_or_errors.size() + " warnings/errors)"
