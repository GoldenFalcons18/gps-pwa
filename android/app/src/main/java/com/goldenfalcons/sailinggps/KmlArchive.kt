package com.goldenfalcons.sailinggps

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import java.util.zip.ZipEntry
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element

/** KML folders -> groups. ZIP entries are read in memory, never extracted to disk. */
object KmlArchive {
    const val MAX_BYTES = 32 * 1024 * 1024
    data class Import(val waypoints: List<Waypoint>, val features: List<MapFeature>, val warnings: List<String> = emptyList())
    private fun children(e: Element) = (0 until e.childNodes.length).mapNotNull { e.childNodes.item(it) as? Element }
    private fun tag(e: Element) = e.localName ?: e.tagName.substringAfter(':')
    private fun direct(e: Element, name: String) = children(e).firstOrNull { tag(it)==name }
    private fun text(e: Element, name: String) = direct(e,name)?.textContent?.trim().orEmpty()
    private fun descendants(e: Element, name: String): List<Element> = children(e).flatMap { (if(tag(it)==name) listOf(it) else emptyList()) + descendants(it,name) }
    private fun escape(s: String) = s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;").replace("'","&apos;")
    private fun coordinates(e: Element): List<MapCoordinate> {
        val raw = descendants(e,"coordinates").firstOrNull()?.textContent.orEmpty()
        return raw.trim().split(Regex("\\s+")).filter { it.isNotBlank() }.map { row -> val a=row.split(','); require(a.size>=2); val p=MapCoordinate(a[1].toDouble(),a[0].toDouble());require(p.lat.isFinite() && p.lon.isFinite() && p.lat in -90.0..90.0 && p.lon in -180.0..180.0);p }.also { require(it.size<=10000) }
    }
    private fun rgb(kml: String): String? = kml.trim().takeIf { Regex("[0-9A-Fa-f]{8}").matches(it) }?.let { "#"+it.substring(6,8)+it.substring(4,6)+it.substring(2,4) }
    private fun kmlColor(rgb: String, alpha: String="ff") = alpha+rgb.substring(5,7)+rgb.substring(3,5)+rgb.substring(1,3)
    fun decode(data: ByteArray): Import {
        require(data.size<=MAX_BYTES) { "32MBを超えています" }
        if (data.take(2)==listOf(80.toByte(),75.toByte())) {
            val points=mutableListOf<Waypoint>();val features=mutableListOf<MapFeature>();val warnings=mutableListOf<String>();var total=0;var entries=0;var files=0
            ZipInputStream(ByteArrayInputStream(data)).use { zip -> while(true) {
                val entry=zip.nextEntry ?: break;require(++entries<=2000) { "ZIP内のファイルが多すぎます" }
                if(!entry.isDirectory && entry.name.lowercase().endsWith(".kml")) {
                    val out=ByteArrayOutputStream();val buffer=ByteArray(8192)
                    while(true) { val n=zip.read(buffer);if(n<0)break;total+=n;require(total<=MAX_BYTES) { "展開したKMLが32MBを超えています" };out.write(buffer,0,n) }
                    val parsed=parse(out.toByteArray());points+=parsed.waypoints;features+=parsed.features;warnings+=parsed.warnings;files++
                    require(points.size<=WaypointArchive.MAX_COUNT && features.size<=1000) { "件数の上限を超えています" }
                }
                zip.closeEntry()
            } }
            require(files>0 && (points.isNotEmpty() || features.isNotEmpty())) { "KMZ内に地点・図形のKMLがありません" };return Import(points,features,warnings.distinct())
        }
        return parse(data).also { require(it.waypoints.isNotEmpty() || it.features.isNotEmpty()) { "取り込める地点・図形がありません" } }
    }
    private fun parse(data: ByteArray): Import {
        val source=data.toString(Charsets.UTF_8)
        require(!source.contains("<!DOCTYPE",true) && !source.contains("<!ENTITY",true)) { "外部参照を含むXMLは読み込めません" }
        val f=DocumentBuilderFactory.newInstance();f.isNamespaceAware=true;f.isExpandEntityReferences=false
        runCatching { f.setFeature("http://apache.org/xml/features/disallow-doctype-decl",true) }
        runCatching { f.setFeature("http://xml.org/sax/features/external-general-entities",false); f.setFeature("http://xml.org/sax/features/external-parameter-entities",false) }
        val root=f.newDocumentBuilder().parse(ByteArrayInputStream(data)).documentElement;require(tag(root)=="kml") { "KML形式ではありません" }
        val points=mutableListOf<Waypoint>();val features=mutableListOf<MapFeature>();val warnings=mutableListOf<String>()
        val styles=descendants(root,"Style").filter { it.hasAttribute("id") }.associateBy { it.getAttribute("id") }
        val maps=descendants(root,"StyleMap").filter { it.hasAttribute("id") }.associate { m -> m.getAttribute("id") to (descendants(m,"Pair").firstOrNull { text(it,"key")=="normal" }?.let { text(it,"styleUrl").removePrefix("#") } ?: "") }
        fun visit(e: Element, group: String, depth: Int) {
            require(depth<=64) { "フォルダが深すぎます" }
            val next=if(tag(e)=="Folder") listOf(group,text(e,"name")).filter { it.isNotBlank() }.joinToString(" / ") else group
            if(tag(e)=="Placemark") {
                val name=text(e,"name").ifEmpty { "ウェイポイント" };val note=text(e,"description").takeIf { it.isNotBlank() }
                val extras=descendants(e,"Data").associate { it.getAttribute("name") to text(it,"value") } + descendants(e,"SimpleData").associate { it.getAttribute("name") to it.textContent.trim() }
                val g=extras["sailing.group"] ?: group
                val styleId=text(e,"styleUrl").removePrefix("#");val style=direct(e,"Style") ?: styles[maps[styleId] ?: styleId]
                val color=extras["sailing.color"] ?: style?.let { descendants(it,"color").firstOrNull()?.textContent?.let(::rgb) } ?: "#FFAA00"
                val href=style?.let { descendants(it,"href").firstOrNull()?.textContent }.orEmpty()
                val mark=extras["sailing.mark"] ?: if(href.contains("pushpin")) "symbol:mappin" else "symbol:flag.fill"
                if(!mark.startsWith("text:") && !mark.startsWith("symbol:")) error("マークの形式が無効です")
                val id=(extras["sailing.id"] ?: extras["uuid"])?.let { runCatching { UUID.fromString(it).toString() }.getOrNull() } ?: UUID.randomUUID().toString()
                for(point in descendants(e,"Point")) { val p=coordinates(point).single();points+=Waypoint(id=if(descendants(e,"Point").size==1) id else UUID.randomUUID().toString(),name=name,lat=p.lat,lon=p.lon,mark=WaypointArchive.displayMark(mark),color=color,note=note,archiveMark=mark,group=g) }
                val kind=extras["sailing.kind"]
                val geometries=descendants(e,"LineString")+descendants(e,"Polygon")
                geometries.forEachIndexed { index, geometry ->
                    var p=coordinates(geometry);if(tag(geometry)=="Polygon" && p.firstOrNull()==p.lastOrNull())p=p.dropLast(1)
                    val shape=kind ?: if(tag(geometry)=="Polygon") "area" else "line"
                    val ids=extras["sailing.waypointIds"]?.split(',')?.filter { it.isNotBlank() }?.map { UUID.fromString(it).toString() } ?: emptyList()
                    val center=extras["sailing.center"]?.split(',')?.takeIf { it.size==2 }?.let { listOf(MapCoordinate(it[0].toDouble(),it[1].toDouble())) }
                    features+=MapFeature(id=if(index==0)id else UUID.randomUUID().toString(),name=name,kind=shape,waypointIds=ids,coordinates=if(shape=="circle")center ?: p.take(1) else p,radius=extras["sailing.radius"]?.toDouble() ?: 200.0,color=color,group=g).also { it.validate() }
                    if(descendants(geometry,"innerBoundaryIs").isNotEmpty())warnings+="穴のあるエリアは外周のみ取り込みました"
                }
                if(descendants(e,"Track").isNotEmpty() || descendants(e,"Model").isNotEmpty())warnings+="軌跡時刻・3Dモデルは取り込み対象外です"
                if(style?.let { descendants(it,"href").isNotEmpty() }==true && extras["sailing.mark"]==null && !href.contains("pushpin")) warnings+="外部アプリの画像マークは旗に置き換えました"
                return
            }
            children(e).forEach { visit(it,next,depth+1) }
        }
        visit(root,"",0);require(points.size<=10000 && features.size<=1000)
        WaypointArchive.encode(points) // shared validation, including text and coordinate limits
        return Import(points,features,warnings.distinct())
    }
    fun encode(points: List<Waypoint>, features: List<MapFeature>, kmz: Boolean): ByteArray {
        WaypointArchive.encode(points);features.forEach { it.validate() }
        fun extra(k: String,v: String)="<Data name=\"$k\"><value>${escape(v)}</value></Data>"
        fun coord(p: List<MapCoordinate>)=p.joinToString(" ") { "${it.lon},${it.lat},0" }
        val xml=buildString {
            append("<?xml version=\"1.0\" encoding=\"UTF-8\"?><kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document><name>Sailing GPS Logger</name>")
            val groups=(points.map { it.group }+features.map { it.group }).distinct()
            for(group in groups) {
                if(group.isNotEmpty())append("<Folder><name>${escape(group)}</name>")
                points.filter { it.group==group }.forEach { w ->
                    append("<Placemark><name>${escape(w.name)}</name><description>${escape(w.note ?: "")}</description><Style><IconStyle><color>${kmlColor(w.color)}</color></IconStyle></Style><ExtendedData>")
                    append(extra("sailing.id",w.id));append(extra("sailing.group",group));append(extra("sailing.color",w.color));append(extra("sailing.mark",WaypointArchive.archiveMark(w)));append("</ExtendedData><Point><coordinates>${w.lon},${w.lat},0</coordinates></Point></Placemark>")
                }
                features.filter { it.group==group }.forEach { f ->
                    val p=f.boundary(points);if(p.size<2)return@forEach
                    append("<Placemark><name>${escape(f.name)}</name><Style><LineStyle><color>${kmlColor(f.color)}</color><width>3</width></LineStyle><PolyStyle><color>${kmlColor(f.color,"40")}</color></PolyStyle></Style><ExtendedData>")
                    append(extra("sailing.id",f.id));append(extra("sailing.group",group));append(extra("sailing.color",f.color));append(extra("sailing.kind",f.kind));append(extra("sailing.radius",f.radius.toString()));append(extra("sailing.waypointIds",f.waypointIds.joinToString(",")))
                    f.points(points).firstOrNull()?.let { append(extra("sailing.center","${it.lat},${it.lon}")) };append("</ExtendedData>")
                    if(f.kind=="line")append("<LineString><tessellate>1</tessellate><coordinates>${coord(p)}</coordinates></LineString>")
                    else append("<Polygon><outerBoundaryIs><LinearRing><coordinates>${coord(p+listOf(p.first()))}</coordinates></LinearRing></outerBoundaryIs></Polygon>")
                    append("</Placemark>")
                }
                if(group.isNotEmpty())append("</Folder>")
            }
            append("</Document></kml>")
        }.toByteArray(Charsets.UTF_8)
        require(xml.size<=MAX_BYTES)
        if(!kmz)return xml
        return ByteArrayOutputStream().also { out -> ZipOutputStream(out).use { z -> z.putNextEntry(ZipEntry("doc.kml"));z.write(xml);z.closeEntry() } }.toByteArray()
    }
}
