import Foundation
/// Visual start templates inspired by the supplied Start Timer reference. Follow the event's sailing instructions.
struct SignalSequence {
    struct Event: Identifiable, Equatable { let id:Int; let secondsBeforeStart:Int; let title:String; let flag:String; let colorHex:UInt32; let raised:Bool; let hornPulses:[Int] }
    struct Profile: Identifiable { let id:String; let name:String; let events:[Event]; var baseDurationMinutes:Int = 5 }
    private static func e(_ id:Int,_ sec:Int,_ title:String,_ flag:String,_ color:UInt32,_ up:Bool,_ pulses:[Int])->Event { Event(id:id,secondsBeforeStart:sec,title:title,flag:flag,colorHex:color,raised:up,hornPulses:pulses) }
    static let profiles:[Profile] = [
        Profile(id:"class-p",name:"Rule 26参考（クラス旗＋P旗）",events:[e(0,300,"クラス旗を掲揚","級",0xF58A00,true,[0]),e(1,240,"P旗を掲揚","P",0x1769FF,true,[0]),e(2,60,"P旗を降下","P",0x1769FF,false,[1]),e(3,0,"クラス旗を降下","級",0xF58A00,false,[0])]),
        Profile(id:"class-i",name:"カスタム（クラス旗＋I旗）",events:[e(0,300,"クラス旗を掲揚","級",0xF58A00,true,[0]),e(1,240,"I旗を掲揚","I",0xF5D328,true,[0]),e(2,60,"I旗を降下","I",0xF5D328,false,[1]),e(3,0,"クラス旗を降下","級",0xF58A00,false,[0])]),
        Profile(id:"class-u",name:"カスタム（クラス旗＋U旗）",events:[e(0,300,"クラス旗を掲揚","級",0xF58A00,true,[0]),e(1,240,"U旗を掲揚","U",0xD72C32,true,[0]),e(2,60,"U旗を降下","U",0xD72C32,false,[1]),e(3,0,"クラス旗を降下","級",0xF58A00,false,[0])]),
        Profile(id:"class-black",name:"カスタム（クラス旗＋黒旗）",events:[e(0,300,"クラス旗を掲揚","級",0xF58A00,true,[0]),e(1,240,"黒旗を掲揚","黒",0x202020,true,[0]),e(2,60,"黒旗を降下","黒",0x202020,false,[1]),e(3,0,"クラス旗を降下","級",0xF58A00,false,[0])]),
        Profile(id:"class-p-i",name:"カスタム（クラス旗＋P旗＋I旗）",events:[e(0,300,"クラス旗を掲揚","級",0xF58A00,true,[0]),e(1,240,"P旗を掲揚","P",0x1769FF,true,[0]),e(2,180,"I旗を掲揚","I",0xF5D328,true,[0]),e(3,120,"I旗を降下","I",0xF5D328,false,[0]),e(4,60,"P旗を降下","P",0x1769FF,false,[1]),e(5,0,"クラス旗を降下","級",0xF58A00,false,[0])]),
        Profile(id:"appendix-v",name:"Appendix V参考（音声のみ）",events:[e(0,180,"3分前・長音×3","♪",0x555555,true,[1,1,1]),e(1,120,"2分前・長音×2","♪",0x555555,true,[1,1]),e(2,90,"1分30秒前・長音＋短音×3","♪",0x555555,true,[1,0,0,0]),e(3,60,"1分前・長音","♪",0x555555,true,[1]),e(4,30,"30秒前・短音×3","♪",0x555555,true,[0,0,0]),e(5,20,"20秒前・短音×2","♪",0x555555,true,[0,0]),e(6,10,"10秒前・短音","♪",0x555555,true,[0]),e(7,5,"5秒前・短音","♪",0x555555,true,[0]),e(8,4,"4秒前・短音","♪",0x555555,true,[0]),e(9,0,"スタート・短音","♪",0x555555,true,[0])],baseDurationMinutes:3)
    ]
    static func events(durationMinutes:Int,profileID:String="class-p")->[Event] {
        let profile=profiles.first{$0.id==profileID} ?? profiles[0], scale=Double(max(1,durationMinutes))/Double(max(1,profile.baseDurationMinutes))
        return profile.events.map { Event(id:$0.id,secondsBeforeStart:Int((Double($0.secondsBeforeStart)*scale).rounded()),title:$0.title,flag:$0.flag,colorHex:$0.colorHex,raised:$0.raised,hornPulses:$0.hornPulses) }
    }
    static func nextEventIndex(secondsUntilStart:Double,durationMinutes:Int=5,profileID:String="class-p")->Int { let es=events(durationMinutes:durationMinutes,profileID:profileID);guard secondsUntilStart>0 else{return es.count-1};return es.firstIndex{secondsUntilStart>Double($0.secondsBeforeStart)} ?? es.count-1 }
    static func secondsUntilNextEvent(secondsUntilStart:Double,index:Int,durationMinutes:Int=5,profileID:String="class-p")->Int { let es=events(durationMinutes:durationMinutes,profileID:profileID);guard es.indices.contains(index) else{return 0};return Int(ceil(secondsUntilStart-Double(es[index].secondsBeforeStart))) }
    static func clockText(_ date:Date,offset:Double=0)->String { let f=DateFormatter();f.locale=Locale(identifier:"ja_JP");f.dateFormat="HH:mm:ss";return f.string(from:date.addingTimeInterval(offset)) }
}