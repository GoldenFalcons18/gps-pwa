package com.goldenfalcons.sailinggps
import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class KmlArchiveTest {
    private val source = """<kml xmlns="http://www.opengis.net/kml/2.2"><Document><Style id="pin"><IconStyle><color>FF0080FF</color><Icon><href>http://maps.google.com/mapfiles/kml/pushpin/ylw-pushpin.png</href></Icon></IconStyle></Style><StyleMap id="normal"><Pair><key>normal</key><styleUrl>#pin</styleUrl></Pair></StyleMap><Folder><name>Group A</name><Placemark><name>A &amp; B</name><ExtendedData><SchemaData><SimpleData name="uuid">00000000-0000-0000-0000-000000000001</SimpleData></SchemaData></ExtendedData><description><![CDATA[note <test>]]></description><styleUrl>#normal</styleUrl><Point><coordinates>10,20,0</coordinates></Point></Placemark></Folder></Document></kml>"""
    @Test fun compassStyleMapAndMultiKml() {
        val zip=ByteArrayOutputStream();ZipOutputStream(zip).use { z ->
            listOf("doc.kml" to "<kml><Document><NetworkLink><Link><href>sub/doc.kml</href></Link></NetworkLink></Document></kml>","sub/doc.kml" to source,"other/doc.kml" to source.replace("Group A","Group B").replace("000000000001","000000000002")).forEach{(name,data)->z.putNextEntry(ZipEntry(name));z.write(data.toByteArray());z.closeEntry()}
        }
        val imported=KmlArchive.decode(zip.toByteArray())
        assertEquals(2,imported.waypoints.size);assertEquals(setOf("Group A","Group B"),imported.waypoints.map{it.group}.toSet())
        val w=imported.waypoints.first();assertEquals("#FF8000",w.color);assertEquals("📍",w.mark);assertEquals("A & B",w.name);assertEquals("note <test>",w.note)
        assertEquals("00000000-0000-0000-0000-000000000001",w.id)
    }
    @Test fun roundTripGeometryAndGroups() {
        val points=KmlArchive.decode(source.toByteArray()).waypoints + listOf(Waypoint(name="two",lat=20.002,lon=10.002,group="Group A"),Waypoint(name="three",lat=20.0,lon=10.003,group="Group A"))
        val features=listOf(MapFeature(name="circle",kind="circle",waypointIds=listOf(points[0].id),radius=321.5),MapFeature(name="area",kind="area",waypointIds=points.map{it.id}),MapFeature(name="line",kind="line",waypointIds=points.take(2).map{it.id}))
        for(kmz in listOf(false,true)) {
            val imported=KmlArchive.decode(KmlArchive.encode(points,features,kmz));assertEquals(3,imported.features.size);assertEquals(321.5,imported.features.first{it.kind=="circle"}.radius,0.001)
            assertEquals(points.map{it.id}.toSet(),imported.waypoints.map{it.id}.toSet());assertEquals(0,WaypointArchive.merge(points,imported.waypoints).added)
            assertEquals(points[0].lat,imported.features.first{it.kind=="circle"}.points(imported.waypoints)[0].lat,0.000001)
        }
        val library=MapLibrary(listOf("Group A"),setOf("Group A"),features);assertEquals(library,MapLibrary.from(library.json().toString()))
    }
    @Test fun folderDefaultColorsRoundTripAndLegacyLibrariesStillLoad() {
        val library=MapLibrary(groups=listOf("Group A"),groupColors=mapOf("Group A" to "#12ABCD"))
        assertEquals("#12ABCD",MapLibrary.from(library.json().toString()).groupColors["Group A"])
        assertTrue(MapLibrary.from("{\"groups\":[\"Old\"]}").groupColors.isEmpty())
    }
    @Test fun rejectsInvalidXmlAndCoordinates() {
        for(bad in listOf(source.replace("10,20,0","10,200,0"),"<!DOCTYPE kml [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><kml>&x;</kml>")) { assertThrows(IllegalArgumentException::class.java){KmlArchive.decode(bad.toByteArray())} }
    }
    @Test fun providedCompassFileWhenAvailable() {
        val path=System.getenv("SAILING_KMZ_TEST") ?: return
        val result=KmlArchive.decode(java.io.File(path).readBytes())
        assertEquals(79,result.waypoints.size);assertEquals(79,result.waypoints.map{it.id}.toSet().size);assertEquals(setOf("#FF8000","#FF00FF","#0000FF","#800080","#FFFFFF","#00C7C7","#00B300","#CC0000"),result.waypoints.map{it.color.uppercase()}.toSet());assertEquals(5,result.waypoints.map{it.group}.distinct().size)
        assertTrue(result.waypoints.all{it.mark=="📍"});assertEquals(0,WaypointArchive.merge(result.waypoints,result.waypoints).added)
        val round=KmlArchive.decode(KmlArchive.encode(result.waypoints,emptyList(),true));assertEquals(0,WaypointArchive.merge(result.waypoints,round.waypoints).added)
    }
}
