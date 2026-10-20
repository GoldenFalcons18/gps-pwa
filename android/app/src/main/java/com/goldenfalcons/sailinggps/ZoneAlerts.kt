package com.goldenfalcons.sailinggps

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** Shared by foreground preview and logging service so the same fix cannot alert twice. */
object ZoneAlerts {
    private val monitor=ZoneMonitor()
    private var configuration=""
    private var libraryRaw=""
    private var itemsRaw=""
    private var zones=emptyList<ZoneMonitor.Zone>()
    @Synchronized fun check(context:Context,point:Location) {
        val prefs=context.getSharedPreferences("display",Context.MODE_PRIVATE)
        if(!prefs.getBoolean("zoneEnabled",false)) {monitor.reset();configuration="";return}
        val keys=listOf("zoneSelected","zoneEnter","zoneExit","zoneAccuracy","zoneMargin","zoneConfirmations")
        val settings=keys.joinToString("|"){prefs.all[it].toString()}
        val storePrefs=context.getSharedPreferences("waypoints",Context.MODE_PRIVATE)
        val raw=storePrefs.getString("library","{}") ?: "{}"
        val items=storePrefs.getString("items","[]") ?: "[]"
        if(settings!=configuration || raw!=libraryRaw || items!=itemsRaw) {
            monitor.reset();configuration=settings;libraryRaw=raw;itemsRaw=items
            val selected=(prefs.getString("zoneSelected","") ?: "").split(",").toSet()
            zones=runCatching {
                val store=WaypointStore(context);val waypoints=store.loadAll()
                store.loadLibrary().features.filter{it.id in selected && it.kind in listOf("circle","area")}.map {
                    ZoneMonitor.Zone(it.id,it.name,if(it.kind=="circle") it.radius else null,it.points(waypoints))
                }
            }.getOrDefault(emptyList())
        }
        val elapsed=android.os.SystemClock.elapsedRealtime()/1000.0
        val events=monitor.update(zones,MapCoordinate(point.latitude,point.longitude),if(point.hasAccuracy()) point.accuracy.toDouble() else Double.NaN,
            point.elapsedRealtimeNanos/1e9,elapsed,prefs.getInt("zoneAccuracy",50).toDouble(),prefs.getInt("zoneMargin",10).toDouble(),prefs.getInt("zoneConfirmations",3))
        events.filter{prefs.getBoolean(if(it.entered) "zoneEnter" else "zoneExit",true)}.forEach { event ->
            if(Build.VERSION.SDK_INT>=33 && ContextCompat.checkSelfPermission(context,Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED) return@forEach
            val manager=context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val sound=prefs.getBoolean("zoneSound",true);val haptic=prefs.getBoolean("zoneHaptic",true)
            val channelId="zone-alert-${if(sound) 1 else 0}-${if(haptic) 1 else 0}"
            val channel=NotificationChannel(channelId,"ゾーンアラート（音${if(sound) "あり" else "なし"}・振動${if(haptic) "あり" else "なし"}）",NotificationManager.IMPORTANCE_HIGH)
            if(!sound) channel.setSound(null,null)
            channel.enableVibration(haptic);manager.createNotificationChannel(channel)
            val intent=PendingIntent.getActivity(context,0,Intent(context,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val message=if(event.entered) "${event.name}に入りました" else "${event.name}から出ました"
            manager.notify("zone-${event.id}",2001,NotificationCompat.Builder(context,channelId).setSmallIcon(android.R.drawable.ic_dialog_alert)
                .setContentTitle("ゾーンアラート").setContentText(message).setContentIntent(intent).setAutoCancel(true).build())
        }
    }
}
