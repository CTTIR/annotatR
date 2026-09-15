/**
 * WRITE TEST: create objects with QuPath 0.7.0's own API in a 200 x 150 px image
 * space (origin top-left, y down) and export them exactly as QuPath does via
 * PathIO.exportObjectsAsGeoJSON.
 *
 * Run from the output directory:
 *   java -Djava.awt.headless=true --enable-native-access=ALL-UNNAMED \
 *     -cp "/opt/QuPath-v0.7.0/lib/app/*" qupath.QuPath script qupath_write_test.groovy
 *
 * Outputs:
 *   qupath_written_objects.geojson         (options: FEATURE_COLLECTION)
 *   qupath_written_objects_array.geojson   (no options; kept only if it differs)
 *   qupath_written_objects_pretty.geojson  (options: FEATURE_COLLECTION, PRETTY_JSON)
 *   qupath_written_expected.json           (independent description built from the
 *                                           script's input values, NOT from the export)
 */
import ch.qos.logback.classic.Logger
import ch.qos.logback.classic.spi.ILoggingEvent
import ch.qos.logback.core.read.ListAppender
import com.google.gson.GsonBuilder
import org.locationtech.jts.geom.Coordinate
import org.locationtech.jts.geom.GeometryFactory
import org.slf4j.LoggerFactory
import qupath.lib.common.ColorTools
import qupath.lib.common.GeneralTools
import qupath.lib.io.PathIO
import qupath.lib.objects.PathObject
import qupath.lib.objects.PathObjects
import qupath.lib.objects.classes.PathClass
import qupath.lib.regions.ImagePlane
import qupath.lib.roi.GeometryTools
import qupath.lib.roi.ROIs

def baseDir = new File(System.getProperty("user.dir"))

def rootLogger = (Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)
def appender = new ListAppender<ILoggingEvent>()
appender.setContext(rootLogger.getLoggerContext())
appender.start()
rootLogger.addAppender(appender)

// ---- helpers ------------------------------------------------------------------
// Packed ARGB int computed by hand (independent of QuPath), as a signed Java int
def packed = { int r, int g, int b -> (int) ((0xFF << 24) | (r << 16) | (g << 8) | b) }
def colourSpec = { int r, int g, int b -> [r: r, g: g, b: b, packed_signed_int: packed(r, g, b)] }
def closeRing = { List pts -> pts + [pts[0]] }

def notes = []
def skipped = []
def objects = []    // PathObjects in export order
def expected = []   // independent descriptions, same order

def defaultPlane = ImagePlane.getDefaultPlane()
def planeSpec = { ImagePlane p -> [c: p.getC(), z: p.getZ(), t: p.getT()] }

// Classification helper: request a class with an explicit colour and make sure the
// (singleton) PathClass really carries that colour.
def classWithColour = { String name, int r, int g, int b ->
    def pc = PathClass.fromString(name, packed(r, g, b))
    if (pc.getColor() == null || pc.getColor() != packed(r, g, b)) {
        notes << "PathClass '${name}' existed with colour ${pc.getColor()}; set explicitly to rgb(${r},${g},${b}) via setColor".toString()
        pc.setColor(r, g, b)
    }
    assert pc.getColor() == ColorTools.packRGB(r, g, b)
    pc
}

def tryCreate = { String key, Closure c ->
    try {
        c.call()
    } catch (Throwable t) {
        skipped << [object: key, reason: t.getClass().getName() + ": " + t.getMessage()]
    }
}

// ---- (a) locked, named rectangle annotation with a fixed UUID ------------------
tryCreate("a") {
    def x = 10d, y = 20d, w = 50d, h = 50d
    def pc = classWithColour("Tumor", 200, 0, 0)
    def roi = ROIs.createRectangleROI(x, y, w, h, defaultPlane)
    def po = PathObjects.createAnnotationObject(roi, pc)
    def fixedId = UUID.fromString("11111111-1111-4111-8111-111111111111")
    po.setID(fixedId)
    po.setName("rect-a")
    po.setLocked(true)
    objects << po
    expected << [key: "a", object_type: "annotation", classification: [name: "Tumor", colour: colourSpec(200, 0, 0)],
                 name: "rect-a", locked: true,
                 roi: [roi_constructor: "ROIs.createRectangleROI(10, 20, 50, 50, ImagePlane.getDefaultPlane())",
                       roi_name_in_memory: roi.getRoiName(), area_px_in_memory: roi.getArea(), length_px_in_memory: roi.getLength(), x: x, y: y, w: w, h: h,
                       vertices_rect_corners_clockwise_from_top_left: closeRing([[10d, 20d], [60d, 20d], [60d, 70d], [10d, 70d]])],
                 plane: planeSpec(defaultPlane), measurements: [:],
                 id: fixedId.toString(), id_source: "fixed UUID set with PathObject.setID()"]
}

// ---- (b) polygon annotation with one hole -------------------------------------
tryCreate("b") {
    def shell = [[100d, 10d], [180d, 10d], [180d, 90d], [100d, 90d]]
    def hole = [[120d, 30d], [150d, 30d], [150d, 60d], [120d, 60d]]
    def gf = GeometryTools.getDefaultFactory()
    def toRing = { List pts -> gf.createLinearRing(closeRing(pts).collect { new Coordinate(it[0], it[1]) } as Coordinate[]) }
    def poly = gf.createPolygon(toRing(shell), [toRing(hole)] as org.locationtech.jts.geom.LinearRing[])
    def roi = GeometryTools.geometryToROI(poly, defaultPlane)
    def pc = classWithColour("Stroma", 0, 160, 0)
    def po = PathObjects.createAnnotationObject(roi, pc)
    objects << po
    expected << [key: "b", object_type: "annotation", classification: [name: "Stroma", colour: colourSpec(0, 160, 0)],
                 name: null, locked: false,
                 roi: [roi_constructor: "GeometryTools.geometryToROI(JTS Polygon(shell, [hole]), ImagePlane.getDefaultPlane())",
                       roi_name_in_memory: roi.getRoiName(), area_px_in_memory: roi.getArea(), length_px_in_memory: roi.getLength(),
                       shell_as_passed: closeRing(shell), holes_as_passed: [closeRing(hole)],
                       area_px_expected: 80d * 80d - 30d * 30d],
                 plane: planeSpec(defaultPlane), measurements: [:],
                 id: po.getID().toString(), id_source: "random UUID assigned by QuPath at creation (read from the in-memory object before export)"]
}

// ---- (c) unclassified ellipse annotation --------------------------------------
tryCreate("c") {
    def roi = ROIs.createEllipseROI(20d, 80d, 40d, 30d, defaultPlane)
    def po = PathObjects.createAnnotationObject(roi)
    objects << po
    expected << [key: "c", object_type: "annotation", classification: null, name: null, locked: false,
                 roi: [roi_constructor: "ROIs.createEllipseROI(20, 80, 40, 30, ImagePlane.getDefaultPlane())",
                       roi_name_in_memory: roi.getRoiName(), area_px_in_memory: roi.getArea(), length_px_in_memory: roi.getLength(), bounding_box: [x: 20d, y: 80d, w: 40d, h: 30d],
                       centre: [x: 40d, y: 95d], semi_axes: [a: 20d, b: 15d],
                       area_px_exact_ellipse: Math.PI * 20d * 15d],
                 plane: planeSpec(defaultPlane), measurements: [:],
                 id: po.getID().toString(), id_source: "random UUID assigned by QuPath at creation (read from the in-memory object before export)"]
}

// ---- (d) detection rectangle with measurements (incl. NaN) ---------------------
tryCreate("d") {
    def pc = classWithColour("Tumor", 200, 0, 0)
    def roi = ROIs.createRectangleROI(70d, 100d, 10d, 10d, defaultPlane)
    def po = PathObjects.createDetectionObject(roi, pc)
    def ml = po.getMeasurementList()
    ml.put("Area px^2", 100d)
    def nanAccepted = true
    try {
        ml.put("Mean", Double.NaN)
    } catch (Throwable t) {
        nanAccepted = false
        notes << "MeasurementList.put('Mean', NaN) threw ${t.getClass().getName()}: ${t.getMessage()}".toString()
    }
    def inMem = po.getMeasurements()
    if (nanAccepted && !(inMem.containsKey("Mean") && Double.isNaN(inMem.get("Mean").doubleValue())))
        notes << "Mean=NaN was accepted by put() but is not present as NaN in memory: ${inMem}".toString()
    try { ml.close() } catch (Throwable ignored) { }
    objects << po
    def meas = new LinkedHashMap()
    meas["Area px^2"] = 100d
    if (nanAccepted) meas["Mean"] = "NaN"
    expected << [key: "d", object_type: "detection", classification: [name: "Tumor", colour: colourSpec(200, 0, 0)],
                 name: null, locked: false,
                 roi: [roi_constructor: "ROIs.createRectangleROI(70, 100, 10, 10, ImagePlane.getDefaultPlane())",
                       roi_name_in_memory: roi.getRoiName(), area_px_in_memory: roi.getArea(), length_px_in_memory: roi.getLength(), x: 70d, y: 100d, w: 10d, h: 10d,
                       vertices_rect_corners_clockwise_from_top_left: closeRing([[70d, 100d], [80d, 100d], [80d, 110d], [70d, 110d]])],
                 plane: planeSpec(defaultPlane),
                 measurements: meas, measurements_note: "NaN is encoded as the string \"NaN\" in THIS expected file only (strict JSON has no NaN)",
                 id: po.getID().toString(), id_source: "random UUID assigned by QuPath at creation (read from the in-memory object before export)"]
}

// ---- (e) cell object with derived classification ------------------------------
tryCreate("e") {
    def cellPts = [[120d, 100d], [140d, 100d], [145d, 115d], [130d, 130d], [115d, 115d]]
    def nucPts = [[125d, 108d], [135d, 108d], [137d, 116d], [130d, 122d], [123d, 116d]]
    def cellRoi = ROIs.createPolygonROI(cellPts.collect { it[0] } as double[], cellPts.collect { it[1] } as double[], defaultPlane)
    def nucRoi = ROIs.createPolygonROI(nucPts.collect { it[0] } as double[], nucPts.collect { it[1] } as double[], defaultPlane)
    def pc = PathClass.fromString("Tumor: Positive")
    def po = PathObjects.createCellObject(cellRoi, nucRoi, pc)
    objects << po
    def pcColour = pc.getColor()
    expected << [key: "e", object_type: "cell", classification: [name: "Tumor: Positive",
                                                                 is_derived: pc.isDerivedClass(),
                                                                 parent: pc.getParentClass()?.toString(),
                                                                 set_as_set: ["Tumor", "Positive"],
                                                                 colour: pcColour == null ? null : [r: ColorTools.red(pcColour), g: ColorTools.green(pcColour), b: ColorTools.blue(pcColour), packed_signed_int: pcColour],
                                                                 colour_source: "not specified by script; QuPath-assigned default for derived class, read via PathClass.getColor() before export"],
                 name: null, locked: false,
                 roi: [roi_constructor: "ROIs.createPolygonROI(xs, ys, ImagePlane.getDefaultPlane())",
                       roi_name_in_memory: cellRoi.getRoiName(), area_px_in_memory: cellRoi.getArea(), length_px_in_memory: cellRoi.getLength(), vertices_as_passed_unclosed: cellPts],
                 nucleus_roi: [roi_constructor: "ROIs.createPolygonROI(xs, ys, ImagePlane.getDefaultPlane())",
                               roi_name_in_memory: nucRoi.getRoiName(), area_px_in_memory: nucRoi.getArea(), length_px_in_memory: nucRoi.getLength(), vertices_as_passed_unclosed: nucPts],
                 plane: planeSpec(defaultPlane), measurements: [:],
                 id: po.getID().toString(), id_source: "random UUID assigned by QuPath at creation (read from the in-memory object before export)"]
}

// ---- (f) line annotation -------------------------------------------------------
tryCreate("f") {
    def roi = ROIs.createLineROI(10d, 140d, 90d, 130d, defaultPlane)
    def po = PathObjects.createAnnotationObject(roi)
    objects << po
    expected << [key: "f", object_type: "annotation", classification: null, name: null, locked: false,
                 roi: [roi_constructor: "ROIs.createLineROI(10, 140, 90, 130, ImagePlane.getDefaultPlane())",
                       roi_name_in_memory: roi.getRoiName(), area_px_in_memory: roi.getArea(), length_px_in_memory: roi.getLength(), vertices_as_passed: [[10d, 140d], [90d, 130d]],
                       length_px_expected: Math.hypot(80d, 10d)],
                 plane: planeSpec(defaultPlane), measurements: [:],
                 id: po.getID().toString(), id_source: "random UUID assigned by QuPath at creation (read from the in-memory object before export)"]
}

// ---- (g) annotation on plane z=2, t=1 ------------------------------------------
tryCreate("g") {
    def plane = ImagePlane.getPlane(2, 1)
    def roi = ROIs.createRectangleROI(150d, 110d, 30d, 20d, plane)
    def po = PathObjects.createAnnotationObject(roi)
    objects << po
    expected << [key: "g", object_type: "annotation", classification: null, name: null, locked: false,
                 roi: [roi_constructor: "ROIs.createRectangleROI(150, 110, 30, 20, ImagePlane.getPlane(2, 1))",
                       roi_name_in_memory: roi.getRoiName(), area_px_in_memory: roi.getArea(), length_px_in_memory: roi.getLength(), x: 150d, y: 110d, w: 30d, h: 20d,
                       vertices_rect_corners_clockwise_from_top_left: closeRing([[150d, 110d], [180d, 110d], [180d, 130d], [150d, 130d]])],
                 plane: [c: -1, z: 2, t: 1], plane_constructor: "ImagePlane.getPlane(2, 1)",
                 measurements: [:],
                 id: po.getID().toString(), id_source: "random UUID assigned by QuPath at creation (read from the in-memory object before export)"]
}

// ---- (h) points annotation with 3 points --------------------------------------
tryCreate("h") {
    def xs = [15.5d, 25d, 35.75d]
    def ys = [130.25d, 135d, 140.5d]
    def pc = classWithColour("Tumor", 200, 0, 0)
    def roi = ROIs.createPointsROI(xs as double[], ys as double[], defaultPlane)
    def po = PathObjects.createAnnotationObject(roi, pc)
    objects << po
    expected << [key: "h", object_type: "annotation", classification: [name: "Tumor", colour: colourSpec(200, 0, 0)],
                 name: null, locked: false,
                 roi: [roi_constructor: "ROIs.createPointsROI(xs, ys, ImagePlane.getDefaultPlane())",
                       roi_name_in_memory: roi.getRoiName(), area_px_in_memory: roi.getArea(), length_px_in_memory: roi.getLength(), points_as_passed: [xs, ys].transpose()],
                 plane: planeSpec(defaultPlane), measurements: [:],
                 id: po.getID().toString(), id_source: "random UUID assigned by QuPath at creation (read from the in-memory object before export)"]
}

// Consistency check of the independent colour packing against QuPath's own packer
assert packed(200, 0, 0) == ColorTools.packRGB(200, 0, 0)
assert packed(0, 160, 0) == ColorTools.packRGB(0, 160, 0)

// ---- export --------------------------------------------------------------------
def exports = []
def doExport = { String fileName, PathIO.GeoJsonExportOptions[] opts ->
    def f = new File(baseDir, fileName)
    try {
        PathIO.exportObjectsAsGeoJSON(f, objects, opts)
        exports << [file: fileName, options: opts.collect { it.toString() }, bytes: f.length()]
    } catch (Throwable t) {
        exports << [file: fileName, options: opts.collect { it.toString() }, error: t.getClass().getName() + ": " + t.getMessage()]
    }
    f
}
def O = PathIO.GeoJsonExportOptions
def fc = doExport("qupath_written_objects.geojson", [O.FEATURE_COLLECTION] as PathIO.GeoJsonExportOptions[])
def arr = doExport("qupath_written_objects_array.geojson", [] as PathIO.GeoJsonExportOptions[])
def pretty = doExport("qupath_written_objects_pretty.geojson", [O.FEATURE_COLLECTION, O.PRETTY_JSON] as PathIO.GeoJsonExportOptions[])

if (arr.exists() && fc.exists() && Arrays.equals(arr.bytes, fc.bytes)) {
    notes << "Export without options was byte-identical to FEATURE_COLLECTION export; array file removed"
    arr.delete()
    exports.find { it.file == arr.getName() }.removed_identical = true
}

rootLogger.detachAppender(appender)
appender.stop()

def result = new LinkedHashMap()
result.description = "Independent description of the objects created by qupath_write_test.groovy, built from the script's input values (not by re-reading the exported GeoJSON)."
result.qupath_version = GeneralTools.getVersion()
result.java_version = System.getProperty("java.version")
result.image_space = [width_px: 200, height_px: 150, origin: "top-left", y_axis: "down", note: "no ImageData/ImageServer used; coordinates are plain image pixel coordinates"]
result.export_order = expected.collect { it.key }
result.objects = expected
result.skipped = skipped
result.exports = exports
result.notes = notes
result.log_events = appender.list.collect { e -> [level: e.getLevel().toString(), logger: e.getLoggerName(), message: e.getFormattedMessage()] }

def gson = new GsonBuilder().setPrettyPrinting().serializeNulls().disableHtmlEscaping().create()
new File(baseDir, "qupath_written_expected.json").withWriter("UTF-8") { it.write(gson.toJson(result)); it.write("\n") }
println "Created ${objects.size()} objects; skipped ${skipped}; exports ${exports}; notes ${notes}"
