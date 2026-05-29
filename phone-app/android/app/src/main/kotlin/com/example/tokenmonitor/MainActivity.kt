package com.example.tokenmonitor

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter 主 Activity
 * 负责注册 Platform Channel 并桥接 Interconnect 原生插件
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "com.example.tokenmonitor/interconnect"
    }

    private lateinit var methodChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val app = application as TokenMonitorApp
        val plugin = app.interconnectPlugin

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        )

        if (plugin != null) {
            plugin.methodChannel = methodChannel
            methodChannel.setMethodCallHandler { call, result ->
                plugin.handleMethodCall(call, result)
            }
        } else {
            // XMS Wearable SDK 不可用，注册空处理器避免 crash
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isConnected" -> result.success(false)
                    "diagnose" -> result.success(mapOf(
                        "connected" to false,
                        "xmsWearableAvailable" to false,
                        "error" to "小米 XMS Wearable SDK 不可用"
                    ))
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        (application as? TokenMonitorApp)?.interconnectPlugin?.dispose()
        super.onDestroy()
    }
}
