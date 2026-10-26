package com.bipulmgr.chuchula

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Bluetooth Classic (RFCOMM) transport for local multiplayer.
 *
 * The host opens one server socket and accepts clients; each client opens a
 * single socket to the host (star topology). Messages are UTF-8 lines; the
 * game protocol on top lives in Dart (lib/multiplayer/local).
 *
 * Secure RFCOMM sockets are used, so the first connection between two
 * phones shows the system pairing dialog. This keeps each player's private
 * cards on an encrypted, authenticated link.
 */
class BluetoothBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("6f3b6c2e-5c1a-4f0e-9a51-7c8a1d2e4b90")
        const val SERVICE_NAME = "ChuchulaGame"
        const val REQ_PERMISSIONS = 7101
        const val REQ_ENABLE = 7102
        const val REQ_DISCOVERABLE = 7103
        private const val MAX_LINE = 256 * 1024
    }

    private val methods = MethodChannel(messenger, "chuchula/bluetooth")
    private val eventChannel = EventChannel(messenger, "chuchula/bluetooth/events")
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private val adapter: BluetoothAdapter? =
        (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    private val connections = ConcurrentHashMap<String, Connection>()
    private val nextId = AtomicInteger(1)
    private val io: ExecutorService = Executors.newCachedThreadPool()

    @Volatile private var serverSocket: BluetoothServerSocket? = null
    @Volatile private var hosting = false
    private var pendingPermissions: MethodChannel.Result? = null
    private var pendingEnable: MethodChannel.Result? = null
    private var pendingDiscoverable: MethodChannel.Result? = null
    private var receiverRegistered = false

    init {
        methods.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    // ---- Event channel ------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    // ---- Permissions ----------------------------------------------------------

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE,
            )
        } else {
            // Classic discovery needs location on Android 11 and lower.
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun hasPermissions(): Boolean = requiredPermissions().all {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    private fun canConnect(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    fun onPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQ_PERMISSIONS) return
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        pendingPermissions?.success(granted)
        pendingPermissions = null
    }

    fun onActivityResult(requestCode: Int, resultCode: Int) {
        when (requestCode) {
            REQ_ENABLE -> {
                pendingEnable?.success(adapter?.isEnabled == true)
                pendingEnable = null
            }
            REQ_DISCOVERABLE -> {
                // resultCode is the discoverable duration, or CANCELED.
                pendingDiscoverable?.success(resultCode != Activity.RESULT_CANCELED)
                pendingDiscoverable = null
            }
        }
    }

    // ---- Method channel -------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "state" -> result.success(
                    mapOf(
                        "supported" to (adapter != null),
                        "enabled" to (adapter?.isEnabled == true),
                        "permissions" to hasPermissions(),
                    ),
                )
                "requestPermissions" -> requestPermissions(result)
                "requestEnable" -> requestEnable(result)
                "makeDiscoverable" -> makeDiscoverable(call.argument<Int>("seconds") ?: 300, result)
                "pairedDevices" -> result.success(pairedDevices())
                "startDiscovery" -> { startDiscovery(); result.success(null) }
                "stopDiscovery" -> { stopDiscovery(); result.success(null) }
                "startServer" -> { startServer(); result.success(null) }
                "stopServer" -> { stopServer(); result.success(null) }
                "connect" -> connect(call.argument<String>("address")!!, result)
                "send" -> {
                    val c = connections[call.argument<String>("id")]
                    if (c == null) {
                        result.error("closed", "Connection is closed", null)
                    } else {
                        c.send(call.argument<String>("data") ?: "")
                        result.success(null)
                    }
                }
                "disconnect" -> {
                    connections[call.argument<String>("id")]?.close()
                    result.success(null)
                }
                "openAppSettings" -> {
                    activity.startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", activity.packageName, null),
                        ),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        } catch (e: Exception) {
            result.error("bluetooth", e.message, null)
        }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasPermissions()) {
            result.success(true)
            return
        }
        pendingPermissions?.success(false)
        pendingPermissions = result
        activity.requestPermissions(requiredPermissions(), REQ_PERMISSIONS)
    }

    @SuppressLint("MissingPermission")
    private fun requestEnable(result: MethodChannel.Result) {
        val a = adapter ?: return result.success(false)
        if (a.isEnabled) return result.success(true)
        if (!canConnect()) return result.success(false)
        pendingEnable?.success(false)
        pendingEnable = result
        @Suppress("DEPRECATION")
        activity.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), REQ_ENABLE)
    }

    @SuppressLint("MissingPermission")
    private fun makeDiscoverable(seconds: Int, result: MethodChannel.Result) {
        val canAdvertise = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE) ==
            PackageManager.PERMISSION_GRANTED
        if (adapter == null || !canAdvertise) return result.success(false)
        pendingDiscoverable?.success(false)
        pendingDiscoverable = result
        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
            .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, seconds)
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, REQ_DISCOVERABLE)
    }

    @SuppressLint("MissingPermission")
    private fun pairedDevices(): List<Map<String, Any?>> {
        val a = adapter ?: return emptyList()
        if (!canConnect()) return emptyList()
        return a.bondedDevices.map { deviceMap(it, paired = true) }
    }

    @SuppressLint("MissingPermission")
    private fun deviceMap(d: BluetoothDevice, paired: Boolean): Map<String, Any?> = mapOf(
        "name" to (if (canConnect()) d.name else null),
        "address" to d.address,
        "paired" to paired,
    )

    private val receiver = object : BroadcastReceiver() {
        @SuppressLint("MissingPermission")
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device: BluetoothDevice? =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                    if (device != null) {
                        val bonded = device.bondState == BluetoothDevice.BOND_BONDED
                        emit(mapOf("type" to "discovered", "device" to deviceMap(device, bonded)))
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> emit(mapOf("type" to "discoveryFinished"))
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startDiscovery() {
        val a = adapter ?: return
        if (!hasPermissions()) throw SecurityException("Bluetooth permissions not granted")
        if (!receiverRegistered) {
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_FOUND)
                addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                activity.registerReceiver(receiver, filter)
            }
            receiverRegistered = true
        }
        if (a.isDiscovering) a.cancelDiscovery()
        a.startDiscovery()
    }

    @SuppressLint("MissingPermission")
    private fun stopDiscovery() {
        try {
            if (hasPermissions()) adapter?.cancelDiscovery()
        } catch (_: SecurityException) {
        }
        if (receiverRegistered) {
            try {
                activity.unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
            }
            receiverRegistered = false
        }
    }

    // ---- Hosting ------------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun startServer() {
        val a = adapter ?: throw IOException("Bluetooth not supported")
        if (!canConnect()) throw SecurityException("BLUETOOTH_CONNECT not granted")
        stopServer()
        val server = a.listenUsingRfcommWithServiceRecord(SERVICE_NAME, SERVICE_UUID)
        serverSocket = server
        hosting = true
        io.execute {
            // Keep accepting until stopped so dropped players can reconnect.
            while (hosting) {
                val socket = try {
                    server.accept()
                } catch (e: IOException) {
                    if (hosting) emit(mapOf("type" to "error", "message" to (e.message ?: "accept failed")))
                    break
                }
                val c = Connection("c${nextId.getAndIncrement()}", socket)
                connections[c.id] = c
                emit(mapOf("type" to "accepted", "id" to c.id, "name" to deviceName(socket)))
                c.start()
            }
        }
    }

    private fun stopServer() {
        hosting = false
        try {
            serverSocket?.close()
        } catch (_: IOException) {
        }
        serverSocket = null
    }

    // ---- Joining --------------------------------------------------------------

    @SuppressLint("MissingPermission")
    private fun connect(address: String, result: MethodChannel.Result) {
        val a = adapter ?: return result.error("unsupported", "Bluetooth not supported", null)
        if (!canConnect()) return result.error("permission", "BLUETOOTH_CONNECT not granted", null)
        io.execute {
            try {
                if (hasPermissions()) a.cancelDiscovery()
                val device = a.getRemoteDevice(address)
                val socket = device.createRfcommSocketToServiceRecord(SERVICE_UUID)
                socket.connect()
                val c = Connection("c${nextId.getAndIncrement()}", socket)
                connections[c.id] = c
                c.start()
                main.post { result.success(mapOf("id" to c.id, "name" to deviceName(socket))) }
            } catch (e: Exception) {
                main.post { result.error("connect-failed", e.message, null) }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun deviceName(socket: BluetoothSocket): String =
        try {
            if (canConnect()) socket.remoteDevice.name ?: socket.remoteDevice.address
            else socket.remoteDevice.address
        } catch (_: SecurityException) {
            socket.remoteDevice.address
        }

    // ---- Connections ----------------------------------------------------------

    private inner class Connection(val id: String, private val socket: BluetoothSocket) {
        private val closed = AtomicBoolean(false)
        private val writer = BufferedWriter(OutputStreamWriter(socket.outputStream, Charsets.UTF_8))
        private val writes: ExecutorService = Executors.newSingleThreadExecutor()

        fun start() {
            io.execute {
                try {
                    val reader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.UTF_8))
                    while (!closed.get()) {
                        val line = reader.readLine() ?: break
                        if (line.length > MAX_LINE) continue
                        emit(mapOf("type" to "line", "id" to id, "data" to line))
                    }
                } catch (_: IOException) {
                } finally {
                    close()
                }
            }
        }

        fun send(line: String) {
            if (closed.get()) return
            writes.execute {
                try {
                    writer.write(line.replace('\n', ' '))
                    writer.write("\n")
                    writer.flush()
                } catch (_: IOException) {
                    close()
                }
            }
        }

        fun close() {
            if (!closed.compareAndSet(false, true)) return
            try {
                socket.close()
            } catch (_: IOException) {
            }
            writes.shutdown()
            connections.remove(id)
            emit(mapOf("type" to "closed", "id" to id))
        }
    }

    fun dispose() {
        stopDiscovery()
        stopServer()
        connections.values.forEach { it.close() }
        io.shutdownNow()
        methods.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }
}
