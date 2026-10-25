package com.goldenfalcons.sailinggps

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import kotlin.concurrent.thread

/** One-shot RFC 5905 client for the public NICT NTP endpoint. */
object NictNtpClient {
    fun sync(callback: (Result<Long>) -> Unit) {
        thread(name = "nict-ntp-sync") {
            val result = runCatching {
                DatagramSocket().use { socket ->
                    socket.soTimeout = 4500
                    val request = ByteArray(48)
                    request[0] = 0x23
                    val address = InetAddress.getByName("ntp.nict.jp")
                    val sentAt = System.currentTimeMillis()
                    socket.send(DatagramPacket(request, request.size, address, 123))
                    val response = ByteArray(512)
                    val packet = DatagramPacket(response, response.size)
                    socket.receive(packet)
                    val receivedAt = System.currentTimeMillis()
                    require(packet.length >= 48) { "NTP response too short" }
                    val seconds = unsignedInt(response, 40)
                    val fraction = unsignedInt(response, 44)
                    val serverMillis = ((seconds - 2_208_988_800L) * 1000L) +
                        ((fraction * 1000.0 / 4_294_967_296.0).toLong())
                    serverMillis - ((sentAt + receivedAt) / 2)
                }
            }
            callback(result)
        }
    }
    private fun unsignedInt(data: ByteArray, offset: Int): Long =
        ((data[offset].toLong() and 0xff) shl 24) or
        ((data[offset + 1].toLong() and 0xff) shl 16) or
        ((data[offset + 2].toLong() and 0xff) shl 8) or
        (data[offset + 3].toLong() and 0xff)
}