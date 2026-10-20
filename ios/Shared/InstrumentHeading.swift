import Foundation

/// COG is true north; declination = true heading - magnetic heading.
enum InstrumentHeading {
    struct Reading:Equatable { var value:Double;var compass:Bool }
    static func normalize(_ value:Double)->Double {(value.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)}
    private static func valid(_ value:Double?)->Double? {value.flatMap{$0.isFinite && $0>=0 && $0<360 ? $0:nil}}
    static func declination(magnetic:Double?,trueHeading:Double?)->Double? {
        guard let magnetic=valid(magnetic),let trueHeading=valid(trueHeading) else {return nil}
        return normalize(trueHeading-magnetic+180)-180
    }
    static func bearing(_ trueBearing:Double?,magnetic:Bool,declination:Double?)->Double? {
        guard let value=valid(trueBearing) else {return nil}
        if !magnetic {return value}
        guard let declination,declination.isFinite else {return nil}
        return normalize(value-declination)
    }
    static func resolve(course:Double?,speed:Double?,magneticHeading:Double?,trueHeading:Double?,magnetic:Bool)->Reading? {
        let correction=declination(magnetic:magneticHeading,trueHeading:trueHeading)
        if let speed,speed.isFinite,speed>=0.25,let course=valid(course) {
            return bearing(course,magnetic:magnetic,declination:correction).map{Reading(value:$0,compass:false)}
        }
        return valid(magnetic ? magneticHeading:trueHeading).map{Reading(value:$0,compass:true)}
    }
}
