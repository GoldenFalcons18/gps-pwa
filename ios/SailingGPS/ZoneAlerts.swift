import CoreLocation
import UserNotifications
import UIKit

final class ZoneAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ZoneAlerts()
    private var monitor=ZoneMonitor()
    private var configuration=""
    private override init() { super.init();UNUserNotificationCenter.current().delegate=self }
    func requestPermission() { UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]) { _,_ in } }
    func check(_ point:CLLocation, library:MapLibrary, waypoints:[Waypoint]) -> String? {
        let prefs=UserDefaults.standard
        guard prefs.bool(forKey:"zoneEnabled") else { monitor.reset();configuration="";return nil }
        let keys=["zoneSelected","zoneEnter","zoneExit","zoneAccuracy","zoneMargin","zoneConfirmations"]
        let key=keys.map{String(describing:prefs.object(forKey:$0))}.joined(separator:"|")
        if key != configuration { monitor.reset();configuration=key }
        let selected=Set((prefs.string(forKey:"zoneSelected") ?? "").split(separator:",").map(String.init))
        let entries=waypoints.map(\.archiveEntry)
        let zones=library.features.filter{selected.contains($0.id.uuidString) && ["circle","area"].contains($0.kind)}.map {
            ZoneMonitor.Zone(id:$0.id.uuidString,name:$0.name,circleRadius:$0.kind=="circle" ? $0.radius:nil,points:$0.points(entries))
        }
        let events=monitor.update(zones:zones,point:.init(latitude:point.coordinate.latitude,longitude:point.coordinate.longitude),accuracy:point.horizontalAccuracy,
                                  timestamp:point.timestamp.timeIntervalSince1970,now:Date().timeIntervalSince1970,
                                  maximumAccuracy:prefs.object(forKey:"zoneAccuracy") as? Double ?? 50,
                                  margin:prefs.object(forKey:"zoneMargin") as? Double ?? 10,
                                  confirmations:prefs.object(forKey:"zoneConfirmations") as? Int ?? 3)
        var latest:String?
        for event in events where prefs.object(forKey:event.entered ? "zoneEnter":"zoneExit") as? Bool ?? true {
            let text="\(event.name)：\(event.entered ? "進入":"退出")を検知"
            let body=event.entered ? "\(event.name)に入りました":"\(event.name)から出ました"
            let content=UNMutableNotificationContent();content.title="ゾーンアラート";content.body=body
            if prefs.object(forKey:"zoneSound") as? Bool ?? true { content.sound = .default }
            UNUserNotificationCenter.current().add(.init(identifier:"zone-"+event.id,content:content,trigger:nil))
            if UIApplication.shared.applicationState == .active, prefs.object(forKey:"zoneHaptic") as? Bool ?? true {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            latest=text
        }
        return latest
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping(UNNotificationPresentationOptions)->Void) {
        completionHandler([.banner,.list,.sound])
    }
}
