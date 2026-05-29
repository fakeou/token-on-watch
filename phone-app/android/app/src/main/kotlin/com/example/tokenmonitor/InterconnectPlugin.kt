package com.example.tokenmonitor

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.auth.AuthApi
import com.xiaomi.xms.wearable.auth.Permission
import com.xiaomi.xms.wearable.message.MessageApi
import com.xiaomi.xms.wearable.message.OnMessageReceivedListener
import com.xiaomi.xms.wearable.node.Node
import com.xiaomi.xms.wearable.node.NodeApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets

/**
 * Interconnect 原生插件
 *
 * 使用小米 XMS Wearable MessageApi 与 Vela 快应用 @system.interconnect 通信。
 * 手机端发送/接收的载荷仍然是 Flutter 层定义的 query/response/push/ping JSON。
 */
class InterconnectPlugin(
    private val context: Context
) {

    companion object {
        private const val TAG = "InterconnectPlugin"
        private const val WATCH_PACKAGE = "com.example.tokenmonitor"
    }

    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    private val nodeApi: NodeApi = Wearable.getNodeApi(appContext)
    private val authApi: AuthApi = Wearable.getAuthApi(appContext)
    private val messageApi: MessageApi = Wearable.getMessageApi(appContext)

    var methodChannel: MethodChannel? = null
    var connected = false
        private set

    private var initialized = false
    private var currentNode: Node? = null
    private var listenerRegisteredNodeId: String? = null
    private var lastCommunicationTime = 0L
    private var lastError: String? = null
    private var appInstalled: Boolean? = null

    private val messageListener = OnMessageReceivedListener { nodeId, bytes ->
        val raw = bytes.toString(StandardCharsets.UTF_8)
        Log.d(TAG, "收到手表消息 nodeId=$nodeId, bytes=${bytes.size}, data=$raw")

        connected = true
        lastCommunicationTime = System.currentTimeMillis()
        notifyConnectionChanged(true)
        onWatchMessageReceived(raw)
    }

    val isReady: Boolean
        get() = true

    init {
        initialize()
    }

    /**
     * 初始化节点、权限和消息监听。
     */
    fun initialize() {
        if (initialized) return
        initialized = true
        refreshConnection()
    }

    /**
     * 主动刷新当前可用节点并注册监听。
     */
    fun refreshConnection() {
        Log.i(TAG, "开始初始化 XMS Wearable 通信")

        nodeApi.getConnectedNodes()
            .addOnSuccessListener { nodes ->
                Log.i(TAG, "已连接设备数量: ${nodes.size}")
                if (nodes.isEmpty()) {
                    setDisconnected("未发现已连接穿戴设备")
                    return@addOnSuccessListener
                }

                val node = nodes.first()
                currentNode = node
                connected = true
                lastError = null
                notifyConnectionChanged(true)
                Log.i(TAG, "使用穿戴设备: id=${node.id}, name=${node.name}")
                checkWearAppInstalled(node.id)

                requestPermissionsAndListen(node.id)
            }
            .addOnFailureListener { e ->
                setDisconnected("获取穿戴设备失败: ${e.message ?: e.javaClass.name}")
                Log.e(TAG, "获取穿戴设备失败", e)
            }
    }

    private fun requestPermissionsAndListen(nodeId: String) {
        authApi.requestPermission(nodeId, Permission.DEVICE_MANAGER, Permission.NOTIFY)
            .addOnSuccessListener { permissions ->
                val granted = permissions.joinToString(",") { it.getName() }
                Log.i(TAG, "穿戴权限申请成功: $granted")
                registerMessageListener(nodeId)
            }
            .addOnFailureListener { e ->
                setDisconnected("穿戴权限申请失败: ${e.message ?: e.javaClass.name}")
                Log.e(TAG, "穿戴权限申请失败", e)
            }
    }

    private fun registerMessageListener(nodeId: String) {
        if (listenerRegisteredNodeId == nodeId) {
            Log.d(TAG, "消息监听已注册: nodeId=$nodeId")
            return
        }

        listenerRegisteredNodeId?.let { oldNodeId ->
            try {
                messageApi.removeListener(oldNodeId)
            } catch (e: Exception) {
                Log.w(TAG, "移除旧消息监听失败: nodeId=$oldNodeId", e)
            }
            listenerRegisteredNodeId = null
        }

        messageApi.addListener(nodeId, messageListener)
            .addOnSuccessListener {
                listenerRegisteredNodeId = nodeId
                connected = true
                lastError = null
                notifyConnectionChanged(true)
                Log.i(TAG, "消息监听注册成功: nodeId=$nodeId")
            }
            .addOnFailureListener { e ->
                setDisconnected("注册消息监听失败: ${e.message ?: e.javaClass.name}")
                Log.e(TAG, "注册消息监听失败", e)
            }
    }

    private fun checkWearAppInstalled(nodeId: String) {
        nodeApi.isWearAppInstalled(WATCH_PACKAGE)
            .addOnSuccessListener { installed ->
                appInstalled = installed
                Log.i(TAG, "快应用安装状态: package=$WATCH_PACKAGE, installed=$installed")
            }
            .addOnFailureListener { e ->
                lastError = "检查快应用安装状态失败: ${e.message ?: e.javaClass.name}"
                Log.w(TAG, lastError, e)
            }
    }

    private fun launchWearApp(nodeId: String) {
        nodeApi.launchWearApp(WATCH_PACKAGE, "/")
            .addOnSuccessListener {
                Log.i(TAG, "快应用启动请求已发送: nodeId=$nodeId")
            }
            .addOnFailureListener { e ->
                lastError = "启动快应用失败: ${e.message ?: e.javaClass.name}"
                Log.w(TAG, lastError, e)
            }
    }

    /**
     * 收到手表端消息后转发到 Flutter。
     */
    fun onWatchMessageReceived(rawData: String) {
        try {
            val watchMessage = parseIncomingMessage(rawData)
            val arguments = HashMap<String, Any?>()
            arguments["action"] = watchMessage.optString("action", "")
            if (watchMessage.has("requestId")) {
                arguments["requestId"] = watchMessage.optString("requestId")
            }
            if (watchMessage.has("sourceId")) {
                arguments["sourceId"] = watchMessage.optString("sourceId")
            }
            arguments["timestamp"] = System.currentTimeMillis().toString()

            watchMessage.optJSONArray("sources")?.let { array ->
                val sourcesList = ArrayList<String>()
                for (i in 0 until array.length()) {
                    sourcesList.add(array.optString(i))
                }
                arguments["sources"] = sourcesList
            }

            watchMessage.optJSONObject("data")?.let { data ->
                arguments["data"] = jsonObjectToMap(data)
            }

            mainHandler.post {
                methodChannel?.invokeMethod("onMessage", arguments)
            }

            Log.d(TAG, "消息已转发到 Flutter: ${watchMessage.optString("action")}")
        } catch (e: Exception) {
            lastError = "消息解析失败: ${e.message ?: e.javaClass.name}"
            Log.e(TAG, "消息解析失败: $rawData", e)
            mainHandler.post {
                methodChannel?.invokeMethod(
                    "onError",
                    mapOf("error" to lastError, "rawData" to rawData)
                )
            }
        }
    }

    fun onWatchMessageReceived(rawData: String, channelEvent: Any?) {
        onWatchMessageReceived(rawData)
    }

    /**
     * Vela conn.send({data}) 到 Android MessageApi 后，常见形态是：
     * 1. 直接业务 JSON: {"action":"query",...}
     * 2. 包裹 JSON: {"id":"...","message":"{\"action\":\"query\"}"}
     */
    private fun parseIncomingMessage(rawData: String): JSONObject {
        val root = JSONObject(rawData)
        if (root.has("action")) return root

        val message = root.opt("message")
        if (message is JSONObject) return message
        if (message is String && message.isNotBlank()) return JSONObject(message)

        return root
    }

    /**
     * 处理来自 Flutter 的方法调用
     */
    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "send" -> {
                val data = call.argument<String>("data")
                if (data != null) {
                    sendToWatch(data, result)
                } else {
                    result.error("INVALID_ARGS", "缺少 data 参数", null)
                }
            }
            "isConnected" -> {
                refreshConnection()
                result.success(connected)
            }
            "diagnose" -> result.success(getDiagnosis())
            "refreshConnection" -> {
                refreshConnection()
                result.success(true)
            }
            "launchWatchApp" -> {
                val node = currentNode
                if (node == null) {
                    refreshConnection()
                    result.error("NO_NODE", "未发现已连接手表", null)
                } else {
                    launchWearApp(node.id)
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * 发送消息到手表快应用。
     */
    private fun sendToWatch(data: String, result: MethodChannel.Result) {
        val node = currentNode
        if (node == null) {
            refreshConnection()
            result.error("NO_NODE", "未发现已连接手表，请先打开手机 App 和手表快应用", null)
            return
        }

        Log.d(TAG, "发送消息到手表 nodeId=${node.id}, data=$data")
        messageApi.sendMessage(node.id, data.toByteArray(StandardCharsets.UTF_8))
            .addOnSuccessListener {
                connected = true
                lastCommunicationTime = System.currentTimeMillis()
                lastError = null
                notifyConnectionChanged(true)
                Log.d(TAG, "发送成功")
                mainHandler.post { result.success(true) }
            }
            .addOnFailureListener { e ->
                lastError = "发送失败: ${e.message ?: e.javaClass.name}"
                Log.e(TAG, "发送失败", e)
                mainHandler.post {
                    result.error("SEND_FAILED", lastError, null)
                }
            }
    }

    fun onConnectionStateChanged(isConnected: Boolean) {
        connected = isConnected
        notifyConnectionChanged(isConnected)
    }

    private fun setDisconnected(error: String) {
        connected = false
        lastError = error
        notifyConnectionChanged(false)
    }

    private fun notifyConnectionChanged(isConnected: Boolean) {
        mainHandler.post {
            methodChannel?.invokeMethod(
                "onConnectionChanged",
                mapOf("connected" to isConnected)
            )
        }
    }

    private fun getDiagnosis(): Map<String, Any?> {
        return mapOf(
            "connected" to connected,
            "lastCommunicationTime" to lastCommunicationTime,
            "watchPackage" to WATCH_PACKAGE,
            "xmsWearableAvailable" to true,
            "currentNodeId" to currentNode?.id,
            "currentNodeName" to currentNode?.name,
            "watchAppInstalled" to appInstalled,
            "listenerRegistered" to (listenerRegisteredNodeId != null),
            "lastError" to lastError,
            "platform" to "Android",
            "deviceModel" to android.os.Build.MODEL,
            "sdkVersion" to android.os.Build.VERSION.SDK_INT,
            "hasChannel" to (methodChannel != null)
        )
    }

    fun dispose() {
        currentNode?.id?.let { nodeId ->
            try {
                messageApi.removeListener(nodeId)
            } catch (e: Exception) {
                Log.w(TAG, "移除消息监听失败", e)
            }
        }
        listenerRegisteredNodeId = null
        connected = false
        methodChannel = null
    }

    private fun jsonObjectToMap(jsonObject: JSONObject): Map<String, Any?> {
        val map = LinkedHashMap<String, Any?>()
        val keys = jsonObject.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = jsonValueToAny(jsonObject.opt(key))
        }
        return map
    }

    private fun jsonArrayToList(jsonArray: JSONArray): List<Any?> {
        val list = ArrayList<Any?>()
        for (i in 0 until jsonArray.length()) {
            list.add(jsonValueToAny(jsonArray.opt(i)))
        }
        return list
    }

    private fun jsonValueToAny(value: Any?): Any? {
        return when (value) {
            JSONObject.NULL -> null
            is JSONObject -> jsonObjectToMap(value)
            is JSONArray -> jsonArrayToList(value)
            else -> value
        }
    }
}
