import Foundation

enum InstrumentSettings {
    static func course(_ course:Double?,speed:Double?,age:Double)->Double? {
        guard age.isFinite,age>=0,age<=15,let speed,speed.isFinite,speed>=0.25,
              let course,course.isFinite,course>=0,course<360 else { return nil }
        return course
    }
    static func coordinate(_ value:Double,isLatitude:Bool,format:String)->String {
        guard value.isFinite else { return "—" }
        if format=="dm" { return CoordinateInput.format(value,isLatitude:isLatitude) }
        let direction=isLatitude ? (value<0 ? "S":"N"):(value<0 ? "W":"E")
        if format=="dd" { return String(format:"%.6f°%@",abs(value),direction) }
        let total=(abs(value)*36000).rounded()/10
        let degrees=Int(total/3600), minutes=Int(total/60)%60, seconds=total.truncatingRemainder(dividingBy:60)
        return String(format:"%d°%02d′%04.1f″%@",degrees,minutes,seconds,direction)
    }
    static func sailingSpeedBand(current:Double?,target:Double,enabled:Bool)->SailingSpeedBand {
        SailingSpeedBand.resolve(current:current,target:target,enabled:enabled)
    }
    static func speedText(_ speed:Double?,factor:Double,zeroThreshold:Double=0)->String {
        guard let speed,speed.isFinite,speed>=0 else { return "—" }
        return String(format:"%.1f",(speed<zeroThreshold ? 0:speed)*factor)
    }
    static func arrival(distance:Double,speed:Double?,now:Date,eta:Bool,twelveHour:Bool)->String {
        let duration=CoordinateInput.ete(distanceMeters:distance,speedMps:speed)
        guard eta, duration != "--:--:--", let speed,speed>0 else { return duration }
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat=twelveHour ? "h:mm:ss a":"HH:mm:ss"
        return formatter.string(from:now.addingTimeInterval(ceil(distance/speed)))
    }
}

enum SailingSpeedBand {
    case belowTarget
    case approximatelyTarget
    case aboveTarget
    case unavailable

    static func resolve(current: Double?, target: Double, enabled: Bool) -> SailingSpeedBand {
        guard enabled else { return .aboveTarget }
        guard let current, current.isFinite, current >= 0, target.isFinite, target >= 0 else { return .unavailable }
        let shownCurrent = (current * 10).rounded()
        let shownTarget = (target * 10).rounded()
        if shownCurrent == shownTarget { return .approximatelyTarget }
        return shownCurrent < shownTarget ? .belowTarget : .aboveTarget
    }
}
