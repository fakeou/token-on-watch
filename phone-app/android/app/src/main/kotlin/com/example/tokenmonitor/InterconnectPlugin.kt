package com.example.tokenmonitor

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Interconnect 原生插件
 * 实现与小米手表 VelaJS 快应用的 interconnect 通信
 * 负责：
 *   1. 注册消息回调监听手表端请求
 *   2. 转发消息到 Flutter 屰处理
 *   3. 将 Flutter 层的响应发送回手表
 */
class InterconnectPlugin(
    private val context: Context,
    private val methodChannel: MethodChannel
) {

    companion object {
        private const val TAG = "InterconnectPlugin"

        // 操作类型常量
        private const val ACTION_QUERY = "query"
        private const val ACTION_RESPONSE = "response"
        private const val ACTION_REFRESH_ONE = "refresh_one"
        private const val ACTION_PUSH = "push"
        private const val ACTION_ERROR = "error"
        private const val ACTION_PING = "ping"
        private const val ACTION_PONG = "pong"
    }

    // 主线程 Handler，用于向 Flutter 发送消息
    private val mainHandler = Handler(Looper.getMainLooper())

    // 连接状态
    private var connected = false

    // interconnect 回调注册标识
    private var callbackRegistered = false

    init {
        // 尝试注册 interconnect 回调
        registerInterconnectCallback()
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
                result.success(connected)
            }

            "diagnose" -> {
                result.success(getDiagnosis())
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * 注册 interconnect 消息回调
     * 监听来自手表端 VelaJS 快应用的消息
     */
    private fun registerInterconnectCallback() {
        try {
            // TODO: 在此处调用小米 interconnect SDK 注册消息回调
            // 示例代码（需要替换为实际的 SDK 调用）：
            //
            // interconnectManager.registerCallback(object : InterconnectCallback {
            //     override fun onMessageReceived(message: String) {
            //         onWatchMessageReceived(message)
            //     }
            //
            //     override fun onConnectionChanged(isConnected: Boolean) {
            //         onConnectionStateChanged(isConnected)
            //     }
            //
            //     override fun onError(error: String) {
            //         onWatchError(error)
            //     }
            // })

            callbackRegistered = true
            Log.i(TAG, "Interconnect 回调注册成功")
        } catch (e: Exception) {
            Log.e(TAG, "Interconnect 回调注册失败", e)
        }
    }

    /**
     * 收到手表端消息时的处理
     * 将消息转发到 Flutter 层
     */
    fun onWatchMessageReceived(message: String) {
        try {
            val json = JSONObject(message)
            val arguments = HashMap<String, Any>()

            arguments["action"] = json.optString("action", "")
            json.opt("requestId")?.let { arguments["requestId"] = it.toString() }
            json.opt("sourceId")?.let { arguments["sourceId"] = it.toString() }
            arguments["timestamp"] = System.currentTimeMillis().toString()

            // 解析 sources 数组
            json.optJSONArray("sources")?.let { array ->
                val sourcesList = ArrayList<String>()
                for (i in 0 until array.length()) {
                    sourcesList.add(array.getString(i))
                }
                arguments["sources"] = sourcesList
            }

            // 通过 Platform Channel 发送到 Flutter
            mainHandler.post {
                methodChannel.invokeMethod("onMessage", arguments)
            }

            Log.d(TAG, "消息已转发到 Flutter: ${json.optString("action")}")
        } catch (e: Exception) {
            Log.e(TAG, "消息解析失败", e)
        }
    }

    /**
     * 连接状态变化回调
     */
    fun onConnectionStateChanged(isConnected: Boolean) {
        connected = isConnected
        mainHandler.post {
            methodChannel.invokeMethod(
                "onConnectionChanged",
                mapOf("connected" to isConnected)
            )
        }
        Log.i(TAG, "手表连接状态: $isConnected")
    }

    /**
     * 错误回调
     */
    fun onWatchError(error: String) {
        mainHandler.post {
            methodChannel.invokeMethod(
                "onError",
                mapOf("error" to error)
            )
        }
        Log.e(TAG, "手表通信错误: $error")
    }

    /**
     * 发送消息到手表端
     */
    private fun sendToWatch(data: String, result: MethodChannel.Result) {
        try {
            // TODO: 在此处调用小米 interconnect SDK 发送消息
            // 示例代码（需要替换为实际的 SDK 调用）：
            //
            // interconnectManager.send(data, object : SendCallback {
            //     override fun onSuccess() {
            //         result.success(true)
            //     }
            //
            //     override fun onFailure(error: String) {
            //         result.error("SEND_FAILED", error, null)
            //     }
            // })

            Log.d(TAG, "消息已发送到手表: $data")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "发送消息失败", e)
            result.error("SEND_FAILED", e.message, null)
        }
    }

    /**
     * 获取诊断信息
     */
    private fun getDiagnosis(): Map<String, Any> {
        return mapOf(
            "connected" to connected,
            "callbackRegistered" to callbackRegistered,
            "platform" to "Android",
            "deviceModel" to android.os.Build.MODEL,
            "sdkVersion" to android.os.Build.VERSION.SDK_INT
        )
    }

    /**
     * 释放资源
     */
    fun dispose() {
        // TODO: 取消 interconnect 回调注册
        // interconnectManager.unregisterCallback()
        callbackRegistered = false
        connected = false
        Log.i(TAG, "Interconnect 插件已释放")
    }
}
