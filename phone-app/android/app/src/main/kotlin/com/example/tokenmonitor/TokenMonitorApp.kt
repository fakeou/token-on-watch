package com.example.tokenmonitor

import android.app.Application
import android.content.pm.PackageManager
import android.util.Log
import dalvik.system.DexClassLoader
import dalvik.system.DexFile
import java.io.File

/**
 * Application 类
 * 负责初始化小米穿戴设备 IPC SDK（如果可用）
 *
 * 解决方案：
 * 1. 系统类路径已暴露 SDK -> 直接使用
 * 2. 否则尝试从 Mi Health APK 动态加载 SDK 类
 * 3. 都不可用则禁用 interconnect
 */
class TokenMonitorApp : Application() {

    // 防止 ServiceConnection 被 GC 回收
    private val activeConnections = mutableListOf<android.content.ServiceConnection>()

    companion object {
        private const val TAG = "TokenMonitorApp"
        private const val MI_HEALTH_PACKAGE = "com.mi.health"

        // Mi Health APK 中的 IPC SDK 类名
        private val IPC_CLASSES = listOf(
            "com.xiaomi.wearable.ipc.IpcApi",
            "com.xiaomi.wearable.ipc.DataHandler",
            "com.xiaomi.wearable.ipc.ChannelEvent",
            "com.xiaomi.wearable.ipc.ServiceCallback",
            "com.xiaomi.wearable.ipc.MessageType"
        )
    }

    var interconnectPlugin: InterconnectPlugin? = null
        private set

    // 动态加载的 ClassLoader（仅在需要时使用）
    var miHealthClassLoader: ClassLoader? = null
        private set

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "Application onCreate")

        // 当前目标是手机 App 与 Vela 快应用互传数据。
        // 使用公开的 XMS Wearable MessageApi；旧 IpcApi/Huami Binder 探针保留在文件中，
        // 但不再作为启动路径。
        initIpcSdk()
    }

    /**
     * 检查系统类路径是否有 SDK
     */
    private fun isIpcAvailableBySystem(): Boolean {
        return try {
            Class.forName("com.xiaomi.wearable.ipc.IpcApi")
            true
        } catch (_: ClassNotFoundException) {
            false
        }
    }

    /**
     * 从可能包含穿戴 IPC SDK 的候选包动态加载 SDK 类
     * 优先：com.mi.health，其次常见的穿戴/互联包
     */
    private fun loadIpcFromMiHealth(): Boolean {
        val candidates = listOf(
            MI_HEALTH_PACKAGE,
            "com.xiaomi.wearable",
            "com.xiaomi.mi_connect",
            "com.xiaomi.mi_connect_service",
            "com.xiaomi.health",
            "com.mi.health.global"
        )

        val pm = packageManager
        for (pkg in candidates) {
            try {
                val info = pm.getPackageInfo(pkg, 0)
                val apkPath = info.applicationInfo?.sourceDir
                if (apkPath.isNullOrEmpty()) {
                    Log.d(TAG, "候选包 $pkg 无 sourceDir，跳过")
                    continue
                }

                Log.i(TAG, "尝试从候选包 $pkg 加载 IPC SDK: $apkPath")
                val classLoader = try {
                    val ctx = createPackageContext(pkg,
                        android.content.Context.CONTEXT_INCLUDE_CODE or android.content.Context.CONTEXT_IGNORE_SECURITY)
                    ctx.classLoader
                } catch (_: Exception) {
                    val optimizedDir = File(cacheDir, "ipc_sdk_dex/$pkg").apply { mkdirs() }
                    DexClassLoader(apkPath, optimizedDir.absolutePath, null, classLoader)
                }

                var allLoaded = true
                for (className in IPC_CLASSES) {
                    try {
                        classLoader.loadClass(className)
                        Log.d(TAG, "✓ $pkg 加载成功: $className")
                    } catch (_: ClassNotFoundException) {
                        Log.w(TAG, "✗ $pkg 加载失败: $className")
                        allLoaded = false
                    }
                }

                if (allLoaded) {
                    miHealthClassLoader = classLoader
                    Log.i(TAG, "IPC SDK 从 $pkg 加载成功")
                    return true
                }
            } catch (_: PackageManager.NameNotFoundException) {
                // 包不存在，继续下一个
            } catch (e: Exception) {
                Log.w(TAG, "候选包 $pkg 加载异常", e)
            }
        }

        Log.w(TAG, "所有候选包均未提供可用 IPC SDK")
        return false
    }

    /**
     * 初始化 IPC SDK
     */
    private fun initIpcSdk() {
        try {
            val plugin = InterconnectPlugin(this)
            if (plugin.isReady) {
                interconnectPlugin = plugin
                Log.i(TAG, "XMS Wearable MessageApi 初始化成功")
            } else {
                Log.w(TAG, "XMS Wearable MessageApi 初始化失败（类存在但实例化失败）")
            }
        } catch (e: Exception) {
            Log.e(TAG, "XMS Wearable MessageApi 初始化异常", e)
        }
    }

    /**
     * 探针：扫描设备上真实存在的穿戴相关能力类并记录方法签名
     */
    private fun probeWearableCore() {
        val candidates = listOf(
            MI_HEALTH_PACKAGE,
            "com.xiaomi.mi_connect_service"
        )

        val targetClasses = listOf(
            "com.xiaomi.wearable.core.client.DataHandlerAdapter",
            "com.xiaomi.wearable.core.client.IDataHandler",
            "com.xiaomi.wearable.core.DataHandlerRemote",
            "com.xiaomi.wearable.core.DataHandlerRemote\$Stub",
            "com.xiaomi.wearable.core.DataHandlerRemote\$Stub\$Proxy",
            "com.xiaomi.wearable.core.IDataHandlerCore",
            "com.xiaomi.wearable.core.IDataHandlerCore\$Stub",
            "com.xiaomi.wearable.core.IDataHandlerCore\$Stub\$Proxy",
            "com.xiaomi.miot.ble.channel.ChannelEvent"
        )

        val pm = packageManager
        for (pkg in candidates) {
            try {
                val classLoader = try {
                    val ctx = createPackageContext(pkg,
                        android.content.Context.CONTEXT_INCLUDE_CODE or android.content.Context.CONTEXT_IGNORE_SECURITY)
                    ctx.classLoader
                } catch (_: Exception) {
                    val info = pm.getPackageInfo(pkg, 0)
                    val apkPath = info.applicationInfo?.sourceDir
                    if (apkPath.isNullOrEmpty()) continue
                    val optimizedDir = File(cacheDir, "wearable_core_probe/$pkg").apply { mkdirs() }
                    DexClassLoader(apkPath, optimizedDir.absolutePath, null, classLoader)
                }

                Log.i(TAG, "[probe] 扫描候选包: $pkg")
                for (clazzName in targetClasses) {
                    val clazz = try {
                        classLoader.loadClass(clazzName)
                    } catch (_: ClassNotFoundException) {
                        Log.w(TAG, "[probe] ✗ $clazzName")
                        continue
                    }

                    Log.i(TAG, "[probe] ✓ $clazzName, interface=${clazz.isInterface}, super=${clazz.superclass?.name}")

                    clazz.declaredConstructors.forEach { c ->
                        Log.d(TAG, "[probe]   ctor: ${c.toGenericString()}")
                    }
                    clazz.declaredMethods.forEach { m ->
                        Log.d(TAG, "[probe]   method: ${m.toGenericString()}")
                    }
                    clazz.declaredFields.forEach { f ->
                        Log.d(TAG, "[probe]   field: ${f.toGenericString()}")
                    }
                }
            } catch (_: PackageManager.NameNotFoundException) {
                // ignore
            } catch (e: Exception) {
                Log.w(TAG, "[probe] $pkg 探针异常", e)
            }
        }

        // 先绑定服务（不依赖 DEX 扫描结果），避免扫描阻塞导致 onServiceConnected 不触发
        probeBindWearableServices()

        // probeMiConnectServiceEntries()  // 暂时跳过 DEX 全量扫描，避免阻塞主线程
    }

    /**
     * 深度探针：枚举 mi_connect_service 中的 Service 子类，定位可绑定入口
     * 采用全量扫描（不过滤类名关键词），避免漏掉真实穿戴服务入口
     */
    private fun probeMiConnectServiceEntries() {
        val pkg = "com.xiaomi.mi_connect_service"
        val pm = packageManager

        try {
            val info = pm.getPackageInfo(pkg, 0)
            val apkPath = info.applicationInfo?.sourceDir
            if (apkPath.isNullOrEmpty()) {
                Log.w(TAG, "[probe-service] $pkg 无 sourceDir")
                return
            }

            val optimizedDir = File(cacheDir, "wearable_core_probe/$pkg/service").apply { mkdirs() }
            val classLoader = DexClassLoader(apkPath, optimizedDir.absolutePath, null, classLoader)

            Log.i(TAG, "[probe-service] 枚举 $pkg 类名（全量）: $apkPath")
            var count = 0
            var serviceCount = 0
            var loadFailCount = 0

            val dexFile = DexFile(apkPath)
            val entries = dexFile.entries()
            while (entries.hasMoreElements()) {
                val name = entries.nextElement()
                count++

                if (count % 2000 == 0) {
                    Log.i(TAG, "[probe-service] 进度: scanned=$count, services=$serviceCount, loadFail=$loadFailCount")
                }

                if (count > 30000) {
                    Log.w(TAG, "[probe-service] 类名超过上限，提前停止")
                    break
                }

                val clazz = try {
                    classLoader.loadClass(name)
                } catch (_: ClassNotFoundException) {
                    loadFailCount++
                    continue
                } catch (_: NoClassDefFoundError) {
                    loadFailCount++
                    continue
                } catch (e: Throwable) {
                    loadFailCount++
                    Log.d(TAG, "[probe-service] loadClass 异常: $name, ${e.message}")
                    continue
                }

                val isService = android.app.Service::class.java.isAssignableFrom(clazz)
                if (!isService) continue

                serviceCount++
                if (serviceCount > 1000) {
                    Log.w(TAG, "[probe-service] service 数量超限，提前停止")
                    break
                }

                Log.i(TAG, "[probe-service] ✓ $name, super=${clazz.superclass?.name}")

                clazz.declaredConstructors.forEach { c ->
                    Log.d(TAG, "[probe-service]   ctor: ${c.toGenericString()}")
                }
                clazz.declaredMethods.forEach { m ->
                    Log.d(TAG, "[probe-service]   method: ${m.toGenericString()}")
                }
                clazz.declaredFields.forEach { f ->
                    Log.d(TAG, "[probe-service]   field: ${f.toGenericString()}")
                }
            }

            dexFile.close()
            Log.i(TAG, "[probe-service] 扫描完成: scanned=$count, services=$serviceCount, loadFail=$loadFailCount")
        } catch (e: Exception) {
            Log.e(TAG, "[probe-service] $pkg 深度探针异常", e)
        }
    }

    /**
     * 最小绑定探针：尝试 bindService 到 MiWearCoreService/MiConnectService，并尝试接口转换
     */
    private fun probeBindWearableServices() {
        // 使用 createPackageContext 获取已优化的 classloader（比 DexClassLoader 快得多）
        val svcClassLoader: ClassLoader? = try {
            val ctx = createPackageContext("com.xiaomi.mi_connect_service",
                android.content.Context.CONTEXT_INCLUDE_CODE or android.content.Context.CONTEXT_IGNORE_SECURITY)
            ctx.classLoader
        } catch (_: Exception) { null }
        val healthClassLoader: ClassLoader? = try {
            val ctx = createPackageContext("com.mi.health",
                android.content.Context.CONTEXT_INCLUDE_CODE or android.content.Context.CONTEXT_IGNORE_SECURITY)
            ctx.classLoader
        } catch (_: Exception) { null }
        Log.i(TAG, "[probe-bind] svcClassLoader=${svcClassLoader?.javaClass?.name}, healthClassLoader=${healthClassLoader?.javaClass?.name}")

        val clCandidates = listOfNotNull(miHealthClassLoader, healthClassLoader, svcClassLoader, javaClass.classLoader)
        Log.i(TAG, "[probe-bind] clCandidates count=${clCandidates.size}")

        val targets = listOf(
            "com.xiaomi.wearable.core.MiWearCoreService" to null,
            "com.xiaomi.mi_connect_service.MiConnectService" to "com.xiaomi.mi_connect_service.MiConnectService",
            "com.xiaomi.mi_connect_service.MiCpp2CppBinder" to "com.xiaomi.mi_connect_service.MiCpp2CppBinder"
        )

        val binderInterfaces = listOf(
            "com.xiaomi.wearable.core.ICoreInstance",
            "com.xiaomi.wearable.core.DataHandlerRemote",
            "com.xiaomi.wearable.core.DataHandlerRemote\$Stub",
            "com.xiaomi.wearable.core.IDataHandlerCore",
            "com.xiaomi.wearable.core.IDataHandlerCore\$Stub"
        )

        // bindService 在主线程调用
        for ((svcName, action) in targets) {
            Log.i(TAG, "[probe-bind] 尝试绑定: $svcName, action=$action")
            try {
                val intent = android.content.Intent()
                intent.setClassName("com.xiaomi.mi_connect_service", svcName)
                action?.let { intent.action = it }
                // 先 startService 确保服务已创建
                try {
                    startService(intent)
                    Log.i(TAG, "[probe-bind]   startService 成功: $svcName")
                } catch (e: Exception) {
                    Log.d(TAG, "[probe-bind]   startService 失败(可忽略): ${e.message}")
                }

                val conn = object : android.content.ServiceConnection {
                    override fun onServiceConnected(name: android.content.ComponentName?, service: android.os.IBinder?) {
                        Log.i(TAG, "[probe-bind] ✓ onServiceConnected: $svcName, binder=${service != null}")
                        try {
                            if (service == null) {
                                Log.w(TAG, "[probe-bind] binder is null")
                                return
                            }

                            Log.d(TAG, "[probe-bind]   binder interface=${service.interfaceDescriptor}")

                            // 反射探针：基于 binder descriptor 加载接口类并记录方法
                            val descriptor = service.interfaceDescriptor

                            val descriptorClass = try {
                                var found: Class<*>? = null
                                for (cl in clCandidates) {
                                    if (cl == null) continue
                                    found = try {
                                        cl.loadClass(descriptor)
                                    } catch (_: ClassNotFoundException) {
                                        null
                                    }
                                    if (found != null) break
                                }
                                found
                            } catch (_: Exception) {
                                null
                            }

                            if (descriptorClass == null) {
                                // descriptor 不在 candidate loaders 中 — 用 DexFile 在两个 APK 中搜索
                                Log.w(TAG, "[probe-bind]   descriptor class '$descriptor' not in candidate loaders, searching APKs...")
                                val searchPkgs = listOf("com.xiaomi.mi_connect_service" to svcClassLoader, "com.mi.health" to miHealthClassLoader)
                                for ((pkg, cl) in searchPkgs) {
                                    try {
                                        val info = packageManager.getPackageInfo(pkg, 0)
                                        val apk = info.applicationInfo?.sourceDir ?: continue
                                        val dex = dalvik.system.DexFile(apk)
                                        val entries = dex.entries()
                                        while (entries.hasMoreElements()) {
                                            val name = entries.nextElement() as String
                                            if (name == descriptor || (descriptor != null && name.endsWith(".${descriptor.substringAfterLast('.')}"))) {
                                                Log.i(TAG, "[probe-bind]   [dex-scan] 候选: $name (in $pkg)")
                                                try {
                                                    val loader = cl ?: javaClass.classLoader
                                                    val clazz = loader.loadClass(name)
                                                    Log.i(TAG, "[probe-bind]   [dex-scan] ✓ 加载成功: $name, iface=${clazz.isInterface}")
                                                    clazz.declaredMethods.forEach { m ->
                                                        Log.i(TAG, "[probe-bind]   [dex-scan]   method: ${m.toGenericString()}")
                                                    }
                                                    // 尝试 asInterface
                                                    try {
                                                        val stub = loader.loadClass("${name}\$Stub")
                                                        val asIntf = stub.methods.firstOrNull { it.name == "asInterface" }
                                                        val proxy = asIntf?.invoke(null, service)
                                                        Log.i(TAG, "[probe-bind]   [dex-scan] proxy -> ${proxy?.javaClass?.name}")
                                                        if (proxy != null) {
                                                            proxy.javaClass.methods.filter { it.declaringClass != Any::class.java }.forEach { m ->
                                                                Log.i(TAG, "[probe-bind]   [dex-scan]   proxy method: ${m.toGenericString()}")
                                                            }
                                                        }
                                                    } catch (e: Exception) {
                                                        val cause = (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e
                                                        Log.w(TAG, "[probe-bind]   [dex-scan] asInterface 异常: ${cause.message}")
                                                    }
                                                } catch (e: Exception) {
                                                    Log.w(TAG, "[probe-bind]   [dex-scan] 加载失败: $name, ${e.message}")
                                                }
                                            }
                                        }
                                        dex.close()
                                    } catch (e: Exception) {
                                        Log.w(TAG, "[probe-bind]   [dex-scan] $pkg 异常: ${e.message}")
                                    }
                                }
                            }

                            if (descriptorClass != null) {
                                Log.i(TAG, "[probe-bind]   descriptor class=${descriptorClass.name}, interface=${descriptorClass.isInterface}, super=${descriptorClass.superclass?.name}")
                                descriptorClass.declaredMethods.forEach { m ->
                                    Log.d(TAG, "[probe-bind]     method: ${m.toGenericString()}")
                                }
                                descriptorClass.declaredFields.forEach { f ->
                                    Log.d(TAG, "[probe-bind]     field: ${f.toGenericString()}")
                                }

                                // 如果是 IMiConnect，尝试调用无参方法验证连接
                                if (descriptor == "com.xiaomi.mi_connect_service.IMiConnect") {
                                    Log.i(TAG, "[probe-bind]   === IMiConnect 连接测试 ===")
                                    // 用 Stub.asInterface 获取 proxy
                                    try {
                                        val stubClass = healthClassLoader?.loadClass("com.xiaomi.mi_connect_service.IMiConnect\$Stub")
                                            ?: svcClassLoader?.loadClass("com.xiaomi.mi_connect_service.IMiConnect\$Stub")
                                        if (stubClass != null) {
                                            val asIntf = stubClass.methods.firstOrNull { it.name == "asInterface" }
                                            val proxy = asIntf?.invoke(null, service)
                                            Log.i(TAG, "[probe-bind]   IMiConnect proxy -> ${proxy?.javaClass?.name}")
                                            if (proxy != null) {
                                                // 调用 getServiceApiVersion
                                                try {
                                                    val ver = proxy.javaClass.getMethod("getServiceApiVersion").invoke(proxy)
                                                    Log.i(TAG, "[probe-bind]   IMiConnect.getServiceApiVersion() -> $ver")
                                                } catch (e: Exception) {
                                                    val cause = (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e
                                                    Log.w(TAG, "[probe-bind]   getServiceApiVersion 异常: ${cause.javaClass.simpleName}: ${cause.message}")
                                                }
                                                // 调用 getIdHash
                                                try {
                                                    val hash = proxy.javaClass.getMethod("getIdHash").invoke(proxy)
                                                    val hashStr = if (hash is ByteArray) hash.joinToString("") { b -> "%02x".format(b) } else "$hash"
                                                    Log.i(TAG, "[probe-bind]   IMiConnect.getIdHash() -> $hashStr")
                                                } catch (e: Exception) {
                                                    val cause = (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e
                                                    Log.w(TAG, "[probe-bind]   getIdHash 异常: ${cause.javaClass.simpleName}: ${cause.message}")
                                                }
                                                // 调用 deviceInfoIDM
                                                try {
                                                    val info = proxy.javaClass.getMethod("deviceInfoIDM").invoke(proxy)
                                                    val infoStr = if (info is ByteArray) String(info) else "$info"
                                                    Log.i(TAG, "[probe-bind]   IMiConnect.deviceInfoIDM() -> $infoStr")
                                                } catch (e: Exception) {
                                                    val cause = (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e
                                                    Log.w(TAG, "[probe-bind]   deviceInfoIDM 异常: ${cause.javaClass.simpleName}: ${cause.message}")
                                                }
                                            }
                                        }
                                    } catch (e: Exception) {
                                        Log.w(TAG, "[probe-bind]   IMiConnect proxy 异常: ${e.message}")
                                    }

                                    // === 通过 Parcel/transact 直接通信，绕过 AIDL 类型检查 ===
                                    try {
                                        val loaders = listOfNotNull(svcClassLoader, healthClassLoader, miHealthClassLoader, javaClass.classLoader)
                                        val miConnectProxy2: Any? = run {
                                            val stub = loaders.firstNotNullOfOrNull { cl ->
                                                try { cl.loadClass("com.xiaomi.mi_connect_service.IMiConnect\$Stub") } catch (_: ClassNotFoundException) { null }
                                            }
                                            stub?.methods?.firstOrNull { it.name == "asInterface" }?.invoke(null, service)
                                        }
                                        if (miConnectProxy2 != null) {
                                            doParcelProbe(miConnectProxy2, svcClassLoader, healthClassLoader)
                                        }
                                    } catch (e: Exception) {
                                        Log.w(TAG, "[probe-parcel] 异常: ${e.javaClass.simpleName}: ${e.message}")
                                    }
                                }

                                // 尝试通过 createPackageContext 获取服务端上下文
                                try {
                                    val svcCtx = createPackageContext("com.xiaomi.mi_connect_service",
                                        android.content.Context.CONTEXT_INCLUDE_CODE or android.content.Context.CONTEXT_IGNORE_SECURITY)
                                    val ctxCl = svcCtx.classLoader
                                    Log.i(TAG, "[probe-bind]   createPackageContext classloader=${ctxCl.javaClass.name}")

                                    // 用服务端 classloader 加载 ICoreInstance$Stub
                                    val ctxStub = try { ctxCl.loadClass("${descriptor}\$Stub") } catch (_: ClassNotFoundException) { null }
                                    if (ctxStub != null) {
                                        val ctxAsIntf = ctxStub.methods.firstOrNull { it.name == "asInterface" }
                                        val ctxProxy = ctxAsIntf?.invoke(null, service)
                                        Log.i(TAG, "[probe-bind]   via createPackageContext asInterface -> ${ctxProxy?.javaClass?.name}")
                                        if (ctxProxy != null) {
                                            try {
                                                val getBinder = ctxProxy.javaClass.methods.first { it.name == "getMiWearCoreBinder" }
                                                val imwBinder = getBinder.invoke(ctxProxy)
                                                Log.i(TAG, "[probe-bind]   [ctx] getMiWearCoreBinder -> class=${imwBinder?.javaClass?.name}, isIBinder=${imwBinder is android.os.IBinder}")
                                                if (imwBinder is android.os.IBinder) {
                                                    Log.i(TAG, "[probe-bind]   [ctx] IMiWearCore descriptor=${imwBinder.interfaceDescriptor}")
                                                    val imwcStub = try { ctxCl.loadClass("com.xiaomi.wearable.core.IMiWearCore\$Stub") } catch (_: ClassNotFoundException) { null }
                                                    if (imwcStub != null) {
                                                        val asIntf2 = imwcStub.methods.firstOrNull { it.name == "asInterface" }
                                                        val imwcProxy = asIntf2?.invoke(null, imwBinder)
                                                        Log.i(TAG, "[probe-bind]   [ctx] IMiWearCore proxy -> ${imwcProxy?.javaClass?.name}")
                                                        if (imwcProxy != null) {
                                                            Log.i(TAG, "[probe-bind]   [ctx] === IMiWearCore methods ===")
                                                            imwcProxy.javaClass.methods.filter { it.declaringClass != Any::class.java }.forEach { m ->
                                                                Log.i(TAG, "[probe-bind]   [ctx]   ${m.toGenericString()}")
                                                            }
                                                        }
                                                    }
                                                }
                                            } catch (e: Exception) {
                                                val cause = (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e.cause ?: e
                                                Log.w(TAG, "[probe-bind]   [ctx] getMiWearCoreBinder 异常: ${cause.javaClass.simpleName}: ${cause.message}")
                                            }
                                        }
                                    }
                                } catch (e: Exception) {
                                    Log.w(TAG, "[probe-bind]   createPackageContext 异常: ${e.javaClass.simpleName}: ${e.message}")
                                }

                                // 尝试通过 $Stub.asInterface 获取 proxy，然后调用 getMiWearCoreBinder
                                val stubClass = clCandidates.firstNotNullOfOrNull { cl ->
                                    try { cl.loadClass("${descriptor}\$Stub") } catch (_: ClassNotFoundException) { null }
                                }
                                if (stubClass != null) {
                                    val asIntf = stubClass.methods.firstOrNull { it.name == "asInterface" }
                                    if (asIntf != null) {
                                        val proxy = asIntf.invoke(null, service)
                                        Log.i(TAG, "[probe-bind]   asInterface via Stub -> ${proxy?.javaClass?.name}")
                                        if (proxy != null) {
                                            proxy.javaClass.methods.filter { it.declaringClass != Any::class.java }.forEach { m ->
                                                Log.i(TAG, "[probe-bind]     proxy: ${m.toGenericString()}")
                                            }
                                            // MiConnectService 探针：绑定后枚举接口方法
                                if (svcName.contains("MiConnectService") && service != null) {
                                    try {
                                        val mcDesc = service.interfaceDescriptor
                                        Log.i(TAG, "[probe-bind]   MiConnectService descriptor=$mcDesc")
                                        val mcStub = clCandidates.firstNotNullOfOrNull { cl ->
                                            try { cl.loadClass("${mcDesc}\$Stub") } catch (_: ClassNotFoundException) { null }
                                        }
                                        if (mcStub != null) {
                                            val mcAsIntf = mcStub.methods.firstOrNull { it.name == "asInterface" }
                                            val mcProxy = mcAsIntf?.invoke(null, service)
                                            Log.i(TAG, "[probe-bind]   MiConnectService proxy -> ${mcProxy?.javaClass?.name}")
                                            if (mcProxy != null) {
                                                Log.i(TAG, "[probe-bind]   === IMiConnectService methods ===")
                                                mcProxy.javaClass.methods.filter { it.declaringClass != Any::class.java }.forEach { m ->
                                                    Log.i(TAG, "[probe-bind]     ${m.toGenericString()}")
                                                }
                                            }
                                        }
                                    } catch (e: Exception) {
                                        Log.w(TAG, "[probe-bind]   MiConnectService 探查异常: ${e.message}")
                                    }
                                }

                                val healthTargets = listOf(
            "com.mi.health/com.xiaomi.wearable.core.MiWearCoreService",
            "com.mi.health/com.xiaomi.fitness.service.DefaultRemoteService",
            "com.mi.health/com.xiaomi.fitness.device.manager.internal.DeviceManagerService"
        )
        val healthActions = mapOf(
            "com.mi.health/com.xiaomi.wearable.core.MiWearCoreService" to "com.mi.health.MiWearCoreService",
            "com.mi.health/com.xiaomi.fitness.service.DefaultRemoteService" to "mi.intent.action.DEFAULT",
            "com.mi.health/com.xiaomi.fitness.device.manager.internal.DeviceManagerService" to "fitness.intent.action.DEVICE"
        )

        for (svcName in healthTargets) {
            Log.i(TAG, "[probe-bind] 尝试绑定 health: $svcName")
            try {
                val intent = android.content.Intent()
                intent.setClassName("com.mi.health", svcName.substringAfter("/"))
                val action = healthActions[svcName]
                if (action != null) intent.action = action

                val conn = object : android.content.ServiceConnection {
                    override fun onServiceConnected(name: android.content.ComponentName?, service: android.os.IBinder?) {
                        Log.i(TAG, "[probe-bind] ✓ health onServiceConnected: $svcName, binder=${service != null}")
                        try {
                            if (service == null) { Log.w(TAG, "[probe-bind] health binder is null"); return }
                            val desc = service.interfaceDescriptor
                            Log.i(TAG, "[probe-bind]   health descriptor=$desc")
                            // 枚举接口方法 — 尝试所有可用 classloader
                            val allLoaders = listOfNotNull(healthClassLoader, svcClassLoader, miHealthClassLoader, javaClass.classLoader)
                            Log.i(TAG, "[probe-bind]   health allLoaders count=${allLoaders.size}, healthCl=${healthClassLoader?.javaClass?.name}")
                            // 也尝试 createPackageContext 获取的 classloader
                            val healthCtxCl = try {
                                val ctx = createPackageContext("com.mi.health", android.content.Context.CONTEXT_INCLUDE_CODE or android.content.Context.CONTEXT_IGNORE_SECURITY)
                                ctx.classLoader
                            } catch (_: Exception) { null }
                            val ctxLoaders = listOfNotNull(healthCtxCl) + allLoaders
                            Log.i(TAG, "[probe-bind]   health ctxLoaders count=${ctxLoaders.size}, ctxCl=${healthCtxCl?.javaClass?.name}")
                            val descClass = ctxLoaders.firstNotNullOfOrNull { cl ->
                                try {
                                    val c = cl.loadClass(desc)
                                    Log.i(TAG, "[probe-bind]   health descClass=$c loaded from ${cl.javaClass.name}")
                                    c
                                } catch (e: ClassNotFoundException) {
                                    Log.d(TAG, "[probe-bind]   health loadClass($desc) failed in ${cl.javaClass.name}")
                                    null
                                }
                            }
                            // IBinderPool 用 Parcel 直接交互（不依赖 classloader）
                            if (desc == "com.xiaomi.fitness.service.IBinderPool") {
                                Log.i(TAG, "[probe-binderpool] === IBinderPool Parcel 探测 ===")
                                // transact(1) = queryBinder, 参数 request 是非空类型
                                // 尝试不同类型的 request 参数
                                // 尝试 String 类型
                                for (reqStr in listOf("default", "miwear", "wearable", "device", "token", "0", "1", "2", "3")) {
                                    try {
                                        val data = android.os.Parcel.obtain()
                                        val reply = android.os.Parcel.obtain()
                                        try {
                                            data.writeInterfaceToken("com.xiaomi.fitness.service.IBinderPool")
                                            data.writeString(reqStr)
                                            service.transact(1, data, reply, 0)
                                            reply.readException()
                                            val binder = reply.readStrongBinder()
                                            Log.i(TAG, "[probe-binderpool]   queryBinder(String=\"$reqStr\") -> binder=$binder")
                                            if (binder != null) {
                                                val innerDesc = try { binder.interfaceDescriptor } catch (_: Exception) { null }
                                                Log.i(TAG, "[probe-binderpool]   queryBinder(\"$reqStr\") descriptor=$innerDesc")
                                            }
                                        } finally { data.recycle(); reply.recycle() }
                                    } catch (e: Exception) {
                                        Log.d(TAG, "[probe-binderpool]   queryBinder(\"$reqStr\") 异常: ${e.javaClass.simpleName}: ${e.message}")
                                    }
                                }
                                // 尝试 Bundle 类型
                                try {
                                    val data = android.os.Parcel.obtain()
                                    val reply = android.os.Parcel.obtain()
                                    try {
                                        data.writeInterfaceToken("com.xiaomi.fitness.service.IBinderPool")
                                        val bundle = android.os.Bundle()
                                        bundle.putString("type", "default")
                                        data.writeBundle(bundle)
                                        service.transact(1, data, reply, 0)
                                        reply.readException()
                                        val binder = reply.readStrongBinder()
                                        Log.i(TAG, "[probe-binderpool]   queryBinder(Bundle) -> binder=$binder")
                                        if (binder != null) {
                                            val innerDesc = try { binder.interfaceDescriptor } catch (_: Exception) { null }
                                            Log.i(TAG, "[probe-binderpool]   queryBinder(Bundle) descriptor=$innerDesc")
                                            // === 探测 IHuamiApiService 的方法 ===
                                            if (innerDesc == "com.xiaomi.wearable.common.connect.IHuamiApiService") {
                                                Log.i(TAG, "[probe-huami] === IHuamiApiService Parcel 探测 ===")
                                                // 尝试 transact codes 1-20
                                                for (code in 1..20) {
                                                    try {
                                                        val d = android.os.Parcel.obtain()
                                                        val r = android.os.Parcel.obtain()
                                                        try {
                                                            d.writeInterfaceToken(innerDesc!!)
                                                            binder.transact(code, d, r, 0)
                                                            r.readException()
                                                            // 尝试读取各种返回类型
                                                            val intVal = r.readInt()
                                                            Log.i(TAG, "[probe-huami]   transact($code) -> readInt=$intVal")
                                                        } finally { d.recycle(); r.recycle() }
                                                    } catch (e: Exception) {
                                                        // 尝试不读 int，看看是否有其他返回
                                                        try {
                                                            val d = android.os.Parcel.obtain()
                                                            val r = android.os.Parcel.obtain()
                                                            try {
                                                                d.writeInterfaceToken(innerDesc!!)
                                                                binder.transact(code, d, r, 0)
                                                                r.readException()
                                                                val str = r.readString()
                                                                Log.i(TAG, "[probe-huami]   transact($code) -> readString=$str")
                                                            } finally { d.recycle(); r.recycle() }
                                                        } catch (e2: Exception) {
                                                            Log.d(TAG, "[probe-huami]   transact($code) 异常: ${e2.javaClass.simpleName}: ${e2.message?.take(100)}")
                                                        }
                                                    }
                                                }
                                                // 也尝试 getServiceApiVersion (transact 1) 只读 exception
                                                try {
                                                    val d = android.os.Parcel.obtain()
                                                    val r = android.os.Parcel.obtain()
                                                    try {
                                                        d.writeInterfaceToken(innerDesc!!)
                                                        binder.transact(1, d, r, 0)
                                                        r.readException()
                                                        Log.i(TAG, "[probe-huami]   transact(1) no-read success, dataAvail=${r.dataAvail()}")
                                                    } finally { d.recycle(); r.recycle() }
                                                } catch (e: Exception) {
                                                    Log.d(TAG, "[probe-huami]   transact(1) 异常: ${e.javaClass.simpleName}: ${e.message?.take(100)}")
                                                }
                                                // 尝试 getHuamiApi(transact 1) 传入手表 MAC 地址
                                                val watchMac = "08:16:D5:9F:86:E7"
                                                try {
                                                    val d = android.os.Parcel.obtain()
                                                    val r = android.os.Parcel.obtain()
                                                    try {
                                                        d.writeInterfaceToken(innerDesc!!)
                                                        d.writeString(watchMac)
                                                        binder.transact(1, d, r, 0)
                                                        r.readException()
                                                        val resultBinder = r.readStrongBinder()
                                                        Log.i(TAG, "[probe-huami]   getHuamiApi(\"$watchMac\") -> result=$resultBinder")
                                                        if (resultBinder != null) {
                                                            val rDesc = try { resultBinder.interfaceDescriptor } catch (_: Exception) { null }
                                                            Log.i(TAG, "[probe-huami]   getHuamiApi -> descriptor=$rDesc")
                                                            // 探测 HuamiApi 关键方法
                                                            if (rDesc != null) {
                                                                Log.i(TAG, "[probe-huami-api] === HuamiApi 关键方法 ===")
                                                                // isConnected (17)
                                                                try { val d2=android.os.Parcel.obtain(); val r2=android.os.Parcel.obtain(); try { d2.writeInterfaceToken(rDesc); resultBinder.transact(17,d2,r2,0); r2.readException(); Log.i(TAG,"[probe-huami-api] isConnected(17)=${r2.readInt()}") } finally { d2.recycle(); r2.recycle() } } catch(e:Exception) { Log.d(TAG,"[probe-huami-api] isConnected 异常: ${e.message?.take(80)}") }
                                                                // connect (13) — 需要 HuamiDeviceCallback 回调
                                                                val cbDesc = "com.xiaomi.wearable.hm.HuamiDeviceCallback"
                                                                val cbBinder = object : android.os.Binder(cbDesc) {
                                                                    override fun onTransact(code: Int, data: android.os.Parcel, reply: android.os.Parcel?, flags: Int): Boolean {
                                                                        when(code) {
                                                                            1 -> { // onConnectionStateChange
                                                                                data.enforceInterface(cbDesc)
                                                                                val s1 = data.readInt(); val s2 = data.readInt(); val s3 = data.readInt()
                                                                                Log.i(TAG, "[probe-huami-cb] onConnectionStateChange($s1, $s2, $s3)")
                                                                                reply?.writeNoException()
                                                                                return true
                                                                            }
                                                                            2 -> { // onGetSignData
                                                                                data.enforceInterface(cbDesc)
                                                                                val p1 = data.readString(); val p2 = data.readString()
                                                                                Log.i(TAG, "[probe-huami-cb] onGetSignData($p1, $p2)")
                                                                                reply?.writeNoException()
                                                                                reply?.writeString("sign_result")
                                                                                return true
                                                                            }
                                                                            3 -> { // onStepChanged
                                                                                data.enforceInterface(cbDesc)
                                                                                Log.i(TAG, "[probe-huami-cb] onStepChanged(dataSize=${data.dataAvail()})")
                                                                                reply?.writeNoException()
                                                                                return true
                                                                            }
                                                                            else -> Log.w(TAG, "[probe-huami-cb] unknown transact($code)")
                                                                        }
                                                                        return super.onTransact(code, data, reply, flags)
                                                                    }
                                                                }
                                                                // initListener(1) + connect(13) + 延迟检查
                                                                try { val d2=android.os.Parcel.obtain(); val r2=android.os.Parcel.obtain(); try { d2.writeInterfaceToken(rDesc); d2.writeStrongBinder(cbBinder); resultBinder.transact(1,d2,r2,0); r2.readException(); Log.i(TAG,"[probe-huami-api] initListener(1) 成功") } finally { d2.recycle(); r2.recycle() } } catch(e:Exception) { Log.d(TAG,"[probe-huami-api] initListener(1) 异常: ${e.message?.take(100)}") }
                                                                try { val d2=android.os.Parcel.obtain(); val r2=android.os.Parcel.obtain(); try { d2.writeInterfaceToken(rDesc); d2.writeStrongBinder(cbBinder); resultBinder.transact(13,d2,r2,0); r2.readException(); Log.i(TAG,"[probe-huami-api] connect(13) 成功") } finally { d2.recycle(); r2.recycle() } } catch(e:Exception) { Log.w(TAG,"[probe-huami-api] connect(13) 异常: ${e.message?.take(100)}") }
                                                                // 延迟 3 秒后再检查
                                                                val huamiBinder = resultBinder
                                                                val huamiDesc = rDesc
                                                                android.os.Handler(mainLooper).postDelayed({
                                                                    try { val d2=android.os.Parcel.obtain(); val r2=android.os.Parcel.obtain(); try { d2.writeInterfaceToken(huamiDesc); huamiBinder.transact(17,d2,r2,0); r2.readException(); Log.i(TAG,"[probe-huami-api] [延迟3s] isConnected(17)=${r2.readInt()}") } finally { d2.recycle(); r2.recycle() } } catch(e:Exception) { Log.d(TAG,"[probe-huami-api] [延迟3s] isConnected 异常: ${e.message?.take(80)}") }
                                                                    try { val d2=android.os.Parcel.obtain(); val r2=android.os.Parcel.obtain(); try { d2.writeInterfaceToken(huamiDesc); huamiBinder.transact(2,d2,r2,0); r2.readException(); val userId=r2.readString(); val phoneId=r2.readString(); val addr=r2.readString(); val model=r2.readString(); val typ=r2.readInt(); val did=r2.readString(); val pn=r2.readString(); val pi=r2.readString(); val dn=r2.readString(); val at=r2.readInt(); val rb=r2.readInt(); val token=r2.readString(); Log.i(TAG,"[probe-huami-api] [延迟3s] getDeviceInfo(2): addr=$addr model=$model did=$did token=$token") } finally { d2.recycle(); r2.recycle() } } catch(e:Exception) { Log.d(TAG,"[probe-huami-api] [延迟3s] getDeviceInfo 异常: ${e.message?.take(100)}") }
                                                                    // openApduChannel
                                                                    try { val d2=android.os.Parcel.obtain(); val r2=android.os.Parcel.obtain(); try { d2.writeInterfaceToken(huamiDesc); huamiBinder.transact(24,d2,r2,0); r2.readException(); val code=r2.readInt(); val msg=r2.readString(); Log.i(TAG,"[probe-huami-api] [延迟3s] openApduChannel(24): code=$code msg=$msg") } finally { d2.recycle(); r2.recycle() } } catch(e:Exception) { Log.d(TAG,"[probe-huami-api] [延迟3s] openApduChannel 异常: ${e.message?.take(100)}") }
                                                                    // getNfcCardInfoSync
                                                                    try { val d2=android.os.Parcel.obtain(); val r2=android.os.Parcel.obtain(); try { d2.writeInterfaceToken(huamiDesc); huamiBinder.transact(38,d2,r2,0); r2.readException(); val code=r2.readInt(); val msg=r2.readString(); Log.i(TAG,"[probe-huami-api] [延迟3s] getNfcCardInfoSync(38): code=$code msg=$msg") } finally { d2.recycle(); r2.recycle() } } catch(e:Exception) { Log.d(TAG,"[probe-huami-api] [延迟3s] getNfcCardInfoSync 异常: ${e.message?.take(100)}") }
                                                                }, 3000)
                                                            }
                                                        }
                                                    } finally { d.recycle(); r.recycle() }
                                                } catch (e: Exception) {
                                                    Log.w(TAG, "[probe-huami]   getHuamiApi(mac) 异常: ${e.javaClass.simpleName}: ${e.message?.take(120)}")
                                                }
                                            }
                                        }
                                    } finally { data.recycle(); reply.recycle() }
                                } catch (e: Exception) {
                                    Log.d(TAG, "[probe-binderpool]   queryBinder(Bundle) 异常: ${e.javaClass.simpleName}: ${e.message}")
                                }
                            }
                            if (descClass != null) {
                                descClass.declaredMethods.forEach { m ->
                                    Log.i(TAG, "[probe-bind]   health method: ${m.toGenericString()}")
                                }
                                // 尝试 asInterface
                                val stubClass = allLoaders.firstNotNullOfOrNull { cl ->
                                    try { cl.loadClass("${desc}\$Stub") } catch (_: ClassNotFoundException) { null }
                                }
                                if (stubClass != null) {
                                    val asIntf = stubClass.methods.firstOrNull { it.name == "asInterface" }
                                    val proxy = asIntf?.invoke(null, service)
                                    Log.i(TAG, "[probe-bind]   health proxy=${proxy?.javaClass?.name}")
                                    if (proxy != null) {
                                        proxy.javaClass.methods.filter { it.declaringClass != Any::class.java }.forEach { m ->
                                            Log.i(TAG, "[probe-bind]   health proxy method: ${m.toGenericString()}")
                                        }
                                        // 尝试调用 getMiWearCoreBinder
                                        try {
                                            val getBinder = proxy.javaClass.methods.firstOrNull { it.name == "getMiWearCoreBinder" }
                                            if (getBinder != null) {
                                                val result = getBinder.invoke(proxy)
                                                Log.i(TAG, "[probe-bind]   health getMiWearCoreBinder -> ${result?.javaClass?.name}, isIBinder=${result is android.os.IBinder}")
                                                if (result is android.os.IBinder) {
                                                    val innerDesc = result.interfaceDescriptor
                                                    Log.i(TAG, "[probe-bind]   health inner descriptor=$innerDesc")
                                                    val innerStub = try { (svcClassLoader ?: javaClass.classLoader).loadClass("${innerDesc}\$Stub") } catch (_: ClassNotFoundException) { null }
                                                    if (innerStub != null) {
                                                        val innerProxy = innerStub.methods.firstOrNull { it.name == "asInterface" }?.invoke(null, result)
                                                        Log.i(TAG, "[probe-bind]   health IMiWearCore proxy=${innerProxy?.javaClass?.name}")
                                                        if (innerProxy != null) {
                                                            Log.i(TAG, "[probe-bind]   === health IMiWearCore methods ===")
                                                            innerProxy.javaClass.methods.filter { it.declaringClass != Any::class.java }.forEach { m ->
                                                                Log.i(TAG, "[probe-bind]   health IMiWearCore: ${m.toGenericString()}")
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        } catch (e: Exception) {
                                            val cause = (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e.cause ?: e
                                            Log.w(TAG, "[probe-bind]   health getMiWearCoreBinder 异常: ${cause.javaClass.simpleName}: ${cause.message}")
                                        }
                                    }
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "[probe-bind] health onServiceConnected 处理异常", e)
                        }
                    }
                    override fun onServiceDisconnected(name: android.content.ComponentName?) {
                        Log.w(TAG, "[probe-bind] health onServiceDisconnected: $svcName")
                    }
                }
                activeConnections.add(conn)
                val ok = bindService(intent, conn, android.content.Context.BIND_AUTO_CREATE)
                Log.i(TAG, "[probe-bind] bindService health: $svcName, ok=$ok")
            } catch (e: Exception) {
                Log.e(TAG, "[probe-bind] 绑定异常 health: $svcName", e)
            }
        }

        // 延迟调用 getMiWearCoreBinder（服务可能需要初始化时间）
                                            val proxyRef = proxy
                                            android.os.Handler(mainLooper).postDelayed({
                                                try {
                                                    Log.i(TAG, "[probe-bind] [delayed] 尝试 getMiWearCoreBinder...")
                                                    val getBinder = proxyRef.javaClass.methods.first { it.name == "getMiWearCoreBinder" }
                                                    val imwBinder = getBinder.invoke(proxyRef)
                                                    Log.i(TAG, "[probe-bind] [delayed] getMiWearCoreBinder -> class=${imwBinder?.javaClass?.name}, isIBinder=${imwBinder is android.os.IBinder}")
                                                    if (imwBinder is android.os.IBinder) {
                                                        Log.i(TAG, "[probe-bind] [delayed] IMiWearCore descriptor=${imwBinder.interfaceDescriptor}")
                                                        val imwcStub = clCandidates.firstNotNullOfOrNull { cl ->
                                                            try { cl.loadClass("com.xiaomi.wearable.core.IMiWearCore\$Stub") } catch (_: ClassNotFoundException) { null }
                                                        }
                                                        if (imwcStub != null) {
                                                            val asIntf2 = imwcStub.methods.firstOrNull { it.name == "asInterface" }
                                                            val imwcProxy = asIntf2?.invoke(null, imwBinder)
                                                            Log.i(TAG, "[probe-bind] [delayed] IMiWearCore proxy -> ${imwcProxy?.javaClass?.name}")
                                                            if (imwcProxy != null) {
                                                                Log.i(TAG, "[probe-bind] [delayed] === IMiWearCore methods ===")
                                                                imwcProxy.javaClass.methods.filter { it.declaringClass != Any::class.java }.forEach { m ->
                                                                    Log.i(TAG, "[probe-bind] [delayed]   ${m.toGenericString()}")
                                                                }
                                                            }
                                                        } else {
                                                            Log.w(TAG, "[probe-bind] [delayed] IMiWearCore\$Stub 未找到")
                                                        }
                                                    }
                                                } catch (e: Exception) {
                                                    val cause = (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e.cause ?: e
                                                    Log.w(TAG, "[probe-bind] [delayed] getMiWearCoreBinder 异常: ${cause.javaClass.simpleName}: ${cause.message}")
                                                }
                                            }, 3000)

                                            // 直接用 DataHandlerRemote 在原始 binder 上调用 handleDataInternal
                                            try {
                                                val dhrStub = clCandidates.firstNotNullOfOrNull { cl ->
                                                    try { cl.loadClass("com.xiaomi.wearable.core.DataHandlerRemote\$Stub") } catch (_: ClassNotFoundException) { null }
                                                }
                                                if (dhrStub != null) {
                                                    val dhrAsIntf = dhrStub.methods.firstOrNull { it.name == "asInterface" }
                                                    val dhrProxy = dhrAsIntf?.invoke(null, service)
                                                    Log.i(TAG, "[probe-bind]   DataHandlerRemote on raw binder -> ${dhrProxy?.javaClass?.name}")
                                                    if (dhrProxy != null) {
                                                        val handleMethod = dhrProxy.javaClass.methods.first { it.name == "handleDataInternal" }
                                                        val result = handleMethod.invoke(dhrProxy, "probe_did", 0, "hello".toByteArray())
                                                        Log.i(TAG, "[probe-bind]   handleDataInternal -> $result")
                                                    }
                                                }
                                            } catch (e: Exception) {
                                                val cause = (e as? java.lang.reflect.InvocationTargetException)?.targetException ?: e.cause ?: e
                                                Log.w(TAG, "[probe-bind]   handleDataInternal 异常: ${cause.javaClass.simpleName}: ${cause.message}")
                                            }
                                        }
                                    } else {
                                        Log.d(TAG, "[probe-bind]   ${descriptor}\$Stub 无 asInterface")
                                    }
                                } else {
                                    Log.w(TAG, "[probe-bind]   ${descriptor}\$Stub 未找到")
                                }
                            } else {
                                Log.w(TAG, "[probe-bind]   descriptor class not found in candidate loaders")
                            }

                            for (iface in binderInterfaces) {
                                try {
                                    var clazz: Class<*>? = null
                                    for (candidate in clCandidates) {
                                        if (candidate == null) continue
                                        clazz = try {
                                            candidate.loadClass(iface)
                                        } catch (_: ClassNotFoundException) {
                                            null
                                        }
                                        if (clazz != null) break
                                    }

                                    if (clazz == null) {
                                        Log.d(TAG, "[probe-bind]   接口类不存在: $iface")
                                        continue
                                    }

                                    val asInterfaceMethod = clazz.methods.firstOrNull { it.name == "asInterface" && it.parameterTypes.contentEquals(arrayOf(android.os.IBinder::class.java)) }
                                    if (asInterfaceMethod != null) {
                                        val proxy = asInterfaceMethod.invoke(null, service)
                                        Log.i(TAG, "[probe-bind]   asInterface OK: $iface -> ${proxy?.javaClass?.name}")
                                        if (proxy != null) {
                                            Log.i(TAG, "[probe-bind]     proxy methods for $iface:")
                                            proxy.javaClass.methods.filter { it.declaringClass != Any::class.java }.forEach { m ->
                                                Log.i(TAG, "[probe-bind]       ${m.toGenericString()}")
                                            }
                                        }
                                    } else {
                                        Log.d(TAG, "[probe-bind]   未找到 asInterface: $iface")
                                    }
                                } catch (e: Exception) {
                                    Log.w(TAG, "[probe-bind]   asInterface 异常: $iface, ${e.message}")
                                }
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "[probe-bind] onServiceConnected 处理异常", e)
                        }
                    }

                    override fun onServiceDisconnected(name: android.content.ComponentName?) {
                        Log.w(TAG, "[probe-bind] onServiceDisconnected: $svcName")
                    }
                }

                activeConnections.add(conn)
                val ok = bindService(intent, conn, android.content.Context.BIND_AUTO_CREATE)
                Log.i(TAG, "[probe-bind] bindService 返回: $svcName, ok=$ok")
            } catch (e: Exception) {
                Log.e(TAG, "[probe-bind] 绑定异常: $svcName", e)
            }
        }
    }

    /**
     * 设置 DataHandler 接收手表消息
     */
    private fun setupDataHandler() {
        val classLoader = miHealthClassLoader ?: javaClass.classLoader
        val ipcApiClass = classLoader!!.loadClass("com.xiaomi.wearable.ipc.IpcApi")
        val dataHandlerClass = classLoader.loadClass("com.xiaomi.wearable.ipc.DataHandler")

        val getMethod = ipcApiClass.getMethod("get")
        val ipcApi = getMethod.invoke(null)

        val initMethod = ipcApiClass.getMethod("init", android.content.Context::class.java)
        initMethod.invoke(ipcApi, this)

        val handler = java.lang.reflect.Proxy.newProxyInstance(
            classLoader,
            arrayOf(dataHandlerClass)
        ) { _, method, args ->
            if (method.name == "onDataReceived") {
                val data = args[0] as String
                val channelEvent = args[1]
                interconnectPlugin?.onWatchMessageReceived(data, channelEvent)
            }
            null
        }

        val setDataHandlerMethod = ipcApiClass.getMethod("setDataHandler", dataHandlerClass)
        setDataHandlerMethod.invoke(ipcApi, handler)
    }

    /**
     * 通过 Parcel/transact 直接与 IMiConnect 通信，绕过 AIDL 类型检查
     */
    private fun doParcelProbe(miConnectProxy: Any, svcCl: ClassLoader? = null, healthCl: ClassLoader? = null) {
        try {
            val allLoaders = listOfNotNull(svcCl, healthCl, miHealthClassLoader, javaClass.classLoader)

            // 1) 获取 Stub 的事务代码
            val stubClass = allLoaders.firstNotNullOfOrNull { cl ->
                try { cl.loadClass("com.xiaomi.mi_connect_service.IMiConnect\$Stub") } catch (_: ClassNotFoundException) { null }
            }
            Log.i(TAG, "[probe-parcel] IMiConnect.Stub=$stubClass")
            val transCodes = mutableMapOf<String, Int>()
            stubClass?.declaredFields?.forEach { f ->
                if (f.name.startsWith("TRANSACTION_")) {
                    f.isAccessible = true
                    val code = f.getInt(null)
                    transCodes[f.name.removePrefix("TRANSACTION_")] = code
                    Log.d(TAG, "[probe-parcel]   ${f.name} = $code")
                }
            }

            // 2) 获取底层 IBinder
            val miBinder = miConnectProxy.javaClass.methods.firstOrNull { it.name == "asBinder" }?.invoke(miConnectProxy) as? android.os.IBinder
            Log.i(TAG, "[probe-parcel] miBinder=$miBinder")

            if (miBinder == null) { Log.w(TAG, "[probe-parcel] miBinder is null"); return }

            // 3) 创建回调 Binder — 用于 registerIDMClient
            val idmDesc = "com.xiaomi.mi_connect_service.IIDMClientCallback"
            val idmBinder = object : android.os.Binder(idmDesc) {
                override fun onTransact(code: Int, data: android.os.Parcel, reply: android.os.Parcel?, flags: Int): Boolean {
                    Log.i(TAG, "[probe-parcel] ★★★ IDM onTransact code=$code, dataAvail=${data.dataAvail()}")
                    try { data.enforceInterface(idmDesc) } catch (_: Exception) {}
                    // 打印原始字节
                    try {
                        val remaining = data.dataAvail()
                        if (remaining > 0) {
                            val bytes = ByteArray(minOf(remaining, 128))
                            data.readByteArray(bytes)
                            Log.i(TAG, "[probe-parcel] ★★★ IDM raw bytes[${bytes.size}]: ${bytes.joinToString("") { "%02x".format(it) }}")
                        }
                    } catch (_: Exception) {}
                    reply?.writeNoException()
                    return true
                }
            }

            // 4) registerIDMClient — 通过 transact 直接调用
            transCodes["registerIDMClient"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        data.writeString("com.example.tokenmonitor")
                        data.writeByteArray(ByteArray(0))
                        data.writeStrongBinder(idmBinder)
                        Log.i(TAG, "[probe-parcel] calling registerIDMClient transact code=$code")
                        miBinder.transact(code, data, reply, 0)
                        reply.readException()
                        val result = reply.readString()
                        Log.i(TAG, "[probe-parcel] ★★★ registerIDMClient 结果=$result")
                    } finally {
                        data.recycle()
                        reply.recycle()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "[probe-parcel] registerIDMClient 异常: ${e.javaClass.simpleName}: ${e.message}")
                }
            }

            // 5) getServiceApiVersion
            transCodes["getServiceApiVersion"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        miBinder.transact(code, data, reply, 0)
                        reply.readException()
                        val ver = reply.readInt()
                        Log.i(TAG, "[probe-parcel] ★★★ getServiceApiVersion=$ver")
                    } finally { data.recycle(); reply.recycle() }
                } catch (e: Exception) { Log.w(TAG, "[probe-parcel] getServiceApiVersion 异常: ${e.message}") }
            }

            // 6) getIdHash
            transCodes["getIdHash"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        miBinder.transact(code, data, reply, 0)
                        reply.readException()
                        val hash = reply.createByteArray()
                        Log.i(TAG, "[probe-parcel] ★★★ getIdHash=${hash?.joinToString("") { "%02x".format(it) }}")
                    } finally { data.recycle(); reply.recycle() }
                } catch (e: Exception) { Log.w(TAG, "[probe-parcel] getIdHash 异常: ${e.message}") }
            }

            // 7) event
            transCodes["event"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        data.writeString("com.example.tokenmonitor")
                        data.writeByteArray(ByteArray(0))
                        miBinder.transact(code, data, reply, 0)
                        reply.readException()
                        val r = reply.readInt()
                        Log.i(TAG, "[probe-parcel] ★★★ event 结果=$r")
                    } finally { data.recycle(); reply.recycle() }
                } catch (e: Exception) { Log.w(TAG, "[probe-parcel] event 异常: ${e.message}") }
            }

            // 8) connectService
            transCodes["connectService"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        data.writeString("com.example.tokenmonitor")
                        data.writeByteArray(ByteArray(0))
                        miBinder.transact(code, data, reply, 0)
                        reply.readException()
                        val r = reply.readInt()
                        Log.i(TAG, "[probe-parcel] ★★★ connectService 结果=$r")
                    } finally { data.recycle(); reply.recycle() }
                } catch (e: Exception) { Log.w(TAG, "[probe-parcel] connectService 异常: ${e.message}") }
            }

            // 9) publish
            transCodes["publish"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        data.writeInt(1)
                        data.writeString("com.example.tokenmonitor")
                        data.writeString("token")
                        data.writeByteArray("hello".toByteArray())
                        miBinder.transact(code, data, reply, 0)
                        reply.readException()
                        val r = reply.readInt()
                        Log.i(TAG, "[probe-parcel] ★★★ publish 结果=$r")
                    } finally { data.recycle(); reply.recycle() }
                } catch (e: Exception) { Log.w(TAG, "[probe-parcel] publish 异常: ${e.message}") }
            }

            // 10) request
            transCodes["request"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        data.writeString("com.example.tokenmonitor")
                        data.writeByteArray("hello".toByteArray())
                        miBinder.transact(code, data, reply, 0)
                        reply.readException()
                        val r = reply.createByteArray()
                        Log.i(TAG, "[probe-parcel] ★★★ request 结果=${r?.size ?: "null"} bytes")
                    } finally { data.recycle(); reply.recycle() }
                } catch (e: Exception) { Log.w(TAG, "[probe-parcel] request 异常: ${e.message}") }
            }

            // 11) setCallback — 设置 IMiConnectCallback
            val miConnectCbDesc = "com.xiaomi.mi_connect_service.IMiConnectCallback"
            val miConnectCbBinder = object : android.os.Binder(miConnectCbDesc) {
                override fun onTransact(code: Int, data: android.os.Parcel, reply: android.os.Parcel?, flags: Int): Boolean {
                    Log.i(TAG, "[probe-parcel] ★★★★ IMiConnectCallback.onTransact code=$code, dataAvail=${data.dataAvail()}")
                    try { data.enforceInterface(miConnectCbDesc) } catch (_: Exception) {}
                    reply?.writeNoException()
                    return true
                }
            }
            transCodes["setCallback"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        data.writeInt(0) // arg1
                        data.writeInt(0) // arg2
                        data.writeStrongBinder(miConnectCbBinder)
                        miBinder.transact(code, data, reply, 0)
                        reply.readException()
                        Log.i(TAG, "[probe-parcel] ★★★ setCallback 完成")
                    } finally { data.recycle(); reply.recycle() }
                } catch (e: Exception) { Log.w(TAG, "[probe-parcel] setCallback 异常: ${e.message}") }
            }

            // 12) startDiscoveryIDM — 发现设备
            transCodes["startDiscoveryIDM"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        data.writeString("com.example.tokenmonitor")
                        data.writeByteArray(ByteArray(0))
                        miBinder.transact(code, data, reply, 0)
                        reply.readException()
                        val r = reply.readString()
                        Log.i(TAG, "[probe-parcel] ★★★ startDiscoveryIDM 结果=$r")
                    } finally { data.recycle(); reply.recycle() }
                } catch (e: Exception) { Log.w(TAG, "[probe-parcel] startDiscoveryIDM 异常: ${e.message}") }
            }

            // 13) createConnection — 创建连接
            val connCbDesc = "com.xiaomi.mi_connect_service.IConnectionCallback"
            val connCbBinder = object : android.os.Binder(connCbDesc) {
                override fun onTransact(code: Int, data: android.os.Parcel, reply: android.os.Parcel?, flags: Int): Boolean {
                    Log.i(TAG, "[probe-parcel] ★★★★ IConnectionCallback.onTransact code=$code, dataAvail=${data.dataAvail()}")
                    try { data.enforceInterface(connCbDesc) } catch (_: Exception) {}
                    reply?.writeNoException()
                    return true
                }
            }
            transCodes["createConnection"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        data.writeString("com.example.tokenmonitor")
                        data.writeByteArray(ByteArray(0))
                        data.writeStrongBinder(connCbBinder)
                        miBinder.transact(code, data, reply, 0)
                        reply.readException()
                        val r = reply.readInt()
                        Log.i(TAG, "[probe-parcel] ★★★ createConnection 结果=$r")
                    } finally { data.recycle(); reply.recycle() }
                } catch (e: Exception) { Log.w(TAG, "[probe-parcel] createConnection 异常: ${e.message}") }
            }

            // 14) requestConnection — 请求连接
            transCodes["requestConnection"]?.let { code ->
                try {
                    val data = android.os.Parcel.obtain()
                    val reply = android.os.Parcel.obtain()
                    try {
                        data.writeInterfaceToken("com.xiaomi.mi_connect_service.IMiConnect")
                        data.writeInt(0) // type
                        data.writeInt(0) // id
                        data.writeByteArray(ByteArray(0)) // token
                        miBinder.transact(code, data, reply, 0)
                        reply?.readException()
                        Log.i(TAG, "[probe-parcel] ★★★ requestConnection 完成")
                    } finally { data.recycle(); reply.recycle() }
                } catch (e: Exception) { Log.w(TAG, "[probe-parcel] requestConnection 异常: ${e.message}") }
            }

            // 15) 延迟 5 秒检查回调
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                Log.i(TAG, "[probe-parcel] ★★★ 5秒后检查 — IDM 回调是否触发")
            }, 5000)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                Log.i(TAG, "[probe-parcel] ★★★ 10秒后检查 — IDM 回调是否触发")
            }, 10000)

        } catch (e: Exception) {
            Log.w(TAG, "[probe-parcel] doParcelProbe 异常: ${e.javaClass.simpleName}: ${e.message}")
            e.printStackTrace()
        }
    }
}
