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
        // Platform Channel 名称
        private const val CHANNEL_NAME = "com.example.tokenmonitor/interconnect"
    }

    private lateinit var methodChannel: MethodChannel
    private var interconnectPlugin: InterconnectPlugin? = null

    /**
     * 配置 Flutter Engine，注册 Platform Channel 和原生插件
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 创建 MethodChannel
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        )

        // 初始化 Interconnect 插件
        interconnectPlugin = InterconnectPlugin(this, methodChannel)

        // 设置来自 Flutter 的方法调用处理器
        methodChannel.setMethodCallHandler { call, result ->
            interconnectPlugin?.handleMethodCall(call, result)
                ?: result.notImplemented()
        }
    }

    /**
     * Activity 销毁时释放资源
     */
    override fun onDestroy() {
        interconnectPlugin?.dispose()
        interconnectPlugin = null
        super.onDestroy()
    }
}
