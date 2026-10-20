import Foundation

/// Baseline silently, then require consecutive unambiguous fixes before a transition.
struct ZoneMonitor {
    struct Zone: Equatable {
        var id: String
        var name: String
        var circleRadius: Double? = nil
        var points: [MapCoordinate]
        func clearance(_ point: MapCoordinate) -> Double? {
            guard point.valid, points.allSatisfy({ $0.valid }) else { return nil }
            if let radius = circleRadius {
                guard radius.isFinite, radius > 0, let center = points.first else { return nil }
                return radius - Self.distance(center, point)
            }
            guard points.count >= 3 else { return nil }
            // Project around the fix; wrap longitude to support the international date line.
            let xy = points.map { p -> (Double,Double) in
                let lon = (p.longitude-point.longitude+540).truncatingRemainder(dividingBy:360)-180
                return (lon * .pi/180 * 6371000 * cos(point.latitude * .pi/180), (p.latitude-point.latitude) * .pi/180 * 6371000)
            }
            var inside = false, nearest = Double.infinity
            for i in xy.indices {
                let a=xy[i], b=xy[(i+1)%xy.count], dx=b.0-a.0, dy=b.1-a.1
                if (a.1>0) != (b.1>0), a.0 + (b.0-a.0) * (-a.1)/(b.1-a.1) > 0 { inside.toggle() }
                let length=dx*dx+dy*dy
                let t=length>0 ? min(1,max(0,-(a.0*dx+a.1*dy)/length)) : 0
                nearest=min(nearest,hypot(a.0+t*dx,a.1+t*dy))
            }
            return inside ? nearest : -nearest
        }
        private static func distance(_ a: MapCoordinate,_ b: MapCoordinate) -> Double {
            let lat=(b.latitude-a.latitude) * .pi/180,lon=(b.longitude-a.longitude) * .pi/180
            let v=pow(sin(lat/2),2)+cos(a.latitude * .pi/180)*cos(b.latitude * .pi/180)*pow(sin(lon/2),2)
            return 12742000 * asin(sqrt(min(1,max(0,v))))
        }
    }
    struct Event { var id:String; var name:String; var entered:Bool }
    private struct State { var zone:Zone; var stable:Bool?; var candidate:Bool?; var count=0; var last=Double.leastNormalMagnitude }
    private var states:[String:State]=[:]
    mutating func reset() { states.removeAll() }
    mutating func update(zones:[Zone], point:MapCoordinate, accuracy:Double, timestamp:Double, now:Double,
                         maximumAccuracy:Double=50, margin:Double=10, confirmations:Int=3) -> [Event] {
        let ids=Set(zones.map(\.id)); states=states.filter{ids.contains($0.key)}
        guard accuracy.isFinite, accuracy>=0, accuracy<=maximumAccuracy, now-timestamp>=0, now-timestamp<=15 else {
            for id in Array(states.keys) { states[id]?.candidate=nil;states[id]?.count=0 };return []
        }
        var events:[Event]=[]
        for zone in zones {
            var state=states[zone.id] ?? State(zone:zone)
            if state.zone != zone { state=State(zone:zone) }
            guard timestamp>state.last else { continue }
            state.last=timestamp
            guard let clearance=zone.clearance(point), abs(clearance)>max(margin,accuracy) else {
                state.candidate=nil;state.count=0;states[zone.id]=state;continue
            }
            let inside=clearance>0
            if state.candidate==inside { state.count += 1 } else { state.candidate=inside;state.count=1 }
            if state.count>=max(1,confirmations), state.stable != inside {
                if state.stable != nil { events.append(Event(id:zone.id,name:zone.name,entered:inside)) }
                state.stable=inside
            }
            states[zone.id]=state
        }
        return events
    }
}
