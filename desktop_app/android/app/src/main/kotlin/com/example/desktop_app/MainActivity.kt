import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import org.java_websocket.client.WebSocketClient
import org.java_websocket.handshake.ServerHandshake
import java.net.URI

class MainActivity : AppCompatActivity() {

    lateinit var client: WebSocketClient

    override fun onCreate(savedInstanceState: Bundle?) {

        super.onCreate(savedInstanceState)

        connectSocket()
    }

    private fun connectSocket() {

        client = object : WebSocketClient(
            URI("ws://YOUR_PC_IP:8080")
        ) {

            override fun onOpen(handshakedata: ServerHandshake?) {

                println("Connected")

                send("Hello from Android")
            }

            override fun onMessage(message: String?) {

                println(message)
            }

            override fun onClose(
                code: Int,
                reason: String?,
                remote: Boolean
            ) {
            }

            override fun onError(ex: Exception?) {

                ex?.printStackTrace()
            }
        }

        client.connect()
    }
}