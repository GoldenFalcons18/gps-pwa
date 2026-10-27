package com.goldenfalcons.sailinggps

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import kotlin.concurrent.thread

object NictClock {
    fun query(onResult:(Result<Long>)->Unit) = thread(name="nict-ntp") {
        try {
            val address=InetAddress.getByName("ntp.nict.jp")
            val request=ByteArray(48).apply { this[0]=0x1b }
            DatagramSocket().use { socket ->
                socket.soTimeout=3500
                val sent=System.currentTimeMillis()
                socket.send(DatagramPacket(request,request.size,address,123))
                val response=ByteArray(48)
                socket.receive(DatagramPacket(response,response.size))
                val received=System.currentTimeMillis()
                val seconds=(40..43).fold(0L){value,index -> (value shl 8) or (response[index].toLong() and 0xff)}
                val fraction=(44..47).fold(0L){value,index -> (value shl 8) or (response[index].toLong() and 0xff)}
                val serverMillis=((seconds-2_208_988_800L)*1000L)+(fraction*1000L/4_294_967_296L)
                val midpoint=sent+(received-sent)/2
                onResult(Result.success(serverMillis-midpoint))
            }
        } catch(error:Throwable) { onResult(Result.failure(error)) }
    }
}
