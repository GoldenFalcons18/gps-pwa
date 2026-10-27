import Foundation
/// Flag sequences are visual templates; always follow the event's sailing instructions.
struct SignalSequence {
    struct Event: Identifiable, Equatable { let id:Int; let secondsBeforeStart:Int; let title:String; let flag:String; let colorHex:UInt32; let raised:Bool }
    struct Profile: Identifiable { let id:String; let name:String; let events:[Event] }
    private static func e(_ id:Int,_ sec:Int,_ title:String,_ flag:String,_ color:UInt32,_ up:Bool)->Event { Event(id:id,secondsBeforeStart:sec,title:title,flag:flag,colorHex:color,raised:up) }
    static let profiles:[Profile] = [
        Profile(id:"class-p",name:"クラス旗＋P旗",events:[e(0,300,"クラス旗を掲揚","級",0xF58A00,true),e(1,240,"P旗を掲揚","P",0x1769FF,true),e(2,60,"P旗を降下","P",0x1769FF,false),e(3,0,"クラス旗を降下","級",0xF58A00,false)]),
        Profile(id:"class-i",name:"クラス旗＋I旗",events:[e(0,300,"クラス旗を掲揚","級",0xF58A00,true),e(1,240,"I旗を掲揚","I",0xF5D328,true),e(2,60,"I旗を降下","I",0xF5D328,false),e(3,0,"クラス旗を降下","級",0xF58A00,false)]),
        Profile(id:"class-u",name:"クラス旗＋U旗",events:[e(0,300,"クラス旗を掲揚","級",0xF58A00,true),e(1,240,"U旗を掲揚","U",0xD72C32,true),e(2,60,"U旗を降下","U",0xD72C32,false),e(3,0,"クラス旗を降下","級",0xF58A00,false)]),
        Profile(id:"class-black",name:"クラス旗＋黒旗",events:[e(0,300,"クラス旗を掲揚","級",0xF58A00,true),e(1,240,"黒旗を掲揚","黒",0x202020,true),e(2,60,"黒旗を降下","黒",0x202020,false),e(3,0,"クラス旗を降下","級",0xF58A00,false)]),
        Profile(id:"class-p-i",name:"クラス旗＋P旗＋I旗",events:[e(0,300,"クラス旗を掲揚","級",0xF58A00,true),e(1,240,"P旗を掲揚","P",0x1769FF,true),e(2,180,"I旗を掲揚","I",0xF5D328,true),e(3,120,"I旗を降下","I",0xF5D328,false),e(4,60,"P旗を降下","P",0x1769FF,false),e(5,0,"クラス旗を降下","級",0xF58A00,false)])
    ]
    static func events(durationMinutes:Int,profileID:String="class-p")->[Event] {
        let scale=Double(max(1,durationMinutes))/5
        return (profiles.first{$0.id==profileID} ?? profiles[0]).events.map { Event(id:$0.id,secondsBeforeStart:Int((Double($0.secondsBeforeStart)*scale).rounded()),title:$0.title,flag:$0.flag,colorHex:$0.colorHex,raised:$0.raised) }
    }
    static func nextEventIndex(secondsUntilStart:Double,durationMinutes:Int=5,profileID:String="class-p")->Int {
        let es=events(durationMinutes:durationMinutes,profileID:profileID)
        guard secondsUntilStart>0 else{return es.count-1}
        return es.firstIndex{secondsUntilStart>=Double($0.secondsBeforeStart)} ?? 0
    }
    static func secondsUntilNextEvent(secondsUntilStart:Double,index:Int,durationMinutes:Int=5,profileID:String="class-p")->Int {
        let es=events(durationMinutes:durationMinutes,profileID:profileID)
        guard es.indices.contains(index) else{return 0}
        return Int(ceil(secondsUntilStart-Double(es[index].secondsBeforeStart)))
    }
    static func clockText(_ date:Date,offset:Double=0)->String {
        let f=DateFormatter();f.locale=Locale(identifier:"ja_JP");f.dateFormat="HH:mm:ss"
        return f.string(from:date.addingTimeInterval(offset))
    }
}