package com.habiboys.lanjo

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {

    private var methodChannel: MethodChannel? = null
    private var pendingNativeAction: Map<String, Any?>? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
        extractIntentAction(intent, notifyFlutter = false)
    }

    override fun onDestroy() {
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractIntentAction(intent, notifyFlutter = true)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CODE_PERMISSION) {
            val result = pendingPermissionResult
            pendingPermissionResult = null
            if (result != null) {
                val allGranted = grantResults.isNotEmpty() &&
                    grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                result.success(allGranted)
            }
        }
    }

    private fun isGranted(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            permission
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun currentPermissionStatuses(): Map<String, Boolean> {
        val notifGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            isGranted(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        }
        val cameraGranted = isGranted(Manifest.permission.CAMERA)
        val photosGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            isGranted(Manifest.permission.READ_MEDIA_IMAGES)
        } else {
            isGranted(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        val micGranted = isGranted(Manifest.permission.RECORD_AUDIO)
        return mapOf(
            "notifications" to notifGranted,
            "camera" to cameraGranted,
            "photos" to photosGranted,
            "microphone" to micGranted
        )
    }

    private fun permissionsForKey(key: String): List<String> {
        val list = mutableListOf<String>()
        when (key) {
            "notifications" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    list.add(Manifest.permission.POST_NOTIFICATIONS)
                }
            }
            "camera" -> list.add(Manifest.permission.CAMERA)
            "photos" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    list.add(Manifest.permission.READ_MEDIA_IMAGES)
                } else {
                    list.add(Manifest.permission.READ_EXTERNAL_STORAGE)
                }
            }
            "microphone" -> list.add(Manifest.permission.RECORD_AUDIO)
            "all" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    list.add(Manifest.permission.POST_NOTIFICATIONS)
                    list.add(Manifest.permission.READ_MEDIA_IMAGES)
                } else {
                    list.add(Manifest.permission.READ_EXTERNAL_STORAGE)
                }
                list.add(Manifest.permission.CAMERA)
                list.add(Manifest.permission.RECORD_AUDIO)
            }
        }
        return list.filter { !isGranted(it) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME
        )
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(
                LanjoWidgetProvider.PREFS_NAME,
                Context.MODE_PRIVATE
            )
            when (call.method) {
                "getInitialNativeAction" -> {
                    val action = pendingNativeAction
                    pendingNativeAction = null
                    result.success(action)
                }

                "getPermissionStatuses" -> {
                    result.success(currentPermissionStatuses())
                }

                "requestPermission" -> {
                    val key = call.argument<String>("key") ?: "all"
                    val missing = permissionsForKey(key)
                    if (missing.isEmpty()) {
                        result.success(true)
                    } else if (pendingPermissionResult != null) {
                        result.success(false)
                    } else {
                        pendingPermissionResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            missing.toTypedArray(),
                            REQ_CODE_PERMISSION
                        )
                    }
                }

                "openAppSettings" -> {
                    try {
                        val settingsIntent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null)
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(settingsIntent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }

                "updateWidget" -> {
                    val title = call.argument<String>("title") ?: "AMAN DIBELANJAKAN / HARI"
                    val safeToSpend = call.argument<String>("safeToSpend") ?: "Rp0"
                    val subtitle = call.argument<String>("subtitle") ?: "Hari ini: Rp0"
                    val badge = call.argument<String>("badge") ?: "Periode aktif"
                    prefs.edit()
                        .putString("widget_title", title)
                        .putString("widget_safe_to_spend", safeToSpend)
                        .putString("widget_subtitle", subtitle)
                        .putString("widget_badge", badge)
                        .apply()
                    LanjoWidgetProvider.updateAllWidgets(applicationContext)
                    result.success(true)
                }

                "getSmartInboxItems" -> {
                    val raw = prefs.getString("smart_inbox_queue", "[]") ?: "[]"
                    result.success(raw)
                }

                "removeSmartInboxItem" -> {
                    val id = call.argument<String>("id") ?: ""
                    val raw = prefs.getString("smart_inbox_queue", "[]") ?: "[]"
                    val arr = try {
                        JSONArray(raw)
                    } catch (_: Exception) {
                        JSONArray()
                    }
                    val next = JSONArray()
                    for (i in 0 until arr.length()) {
                        val obj = arr.optJSONObject(i) ?: continue
                        if (obj.optString("id") != id) {
                            next.put(obj)
                        }
                    }
                    prefs.edit().putString("smart_inbox_queue", next.toString()).apply()
                    result.success(true)
                }

                "clearSmartInbox" -> {
                    prefs.edit().putString("smart_inbox_queue", "[]").apply()
                    result.success(true)
                }

                "enqueueSmartText" -> {
                    val title = call.argument<String>("title") ?: "Notifikasi Terdeteksi"
                    val body = call.argument<String>("body") ?: ""
                    val pkg = call.argument<String>("app") ?: ""
                    val created = LanjoNotificationListener.parseAndEnqueue(
                        context = applicationContext,
                        packageName = pkg,
                        title = title,
                        body = body,
                        requireKnownAppOrKeyword = false
                    )
                    result.success(created?.toString())
                }

                "isNotificationListenerEnabled" -> {
                    val enabled = NotificationManagerCompat
                        .getEnabledListenerPackages(this)
                        .contains(packageName)
                    result.success(enabled)
                }

                "openNotificationListenerSettings" -> {
                    try {
                        val settingsIntent = Intent(
                            Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(settingsIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "getAutoDetectEnabled" -> {
                    result.success(prefs.getBoolean("auto_detect_enabled", true))
                }

                "setAutoDetectEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    prefs.edit().putBoolean("auto_detect_enabled", enabled).apply()
                    result.success(true)
                }

                "simulateBankNotification" -> {
                    val app = call.argument<String>("app") ?: "com.gojek.app"
                    val title = call.argument<String>("title") ?: "Pembayaran QRIS Berhasil"
                    val body = call.argument<String>("body")
                        ?: "Kamu berhasil membayar Rp28.500 di Kopi Kenangan menggunakan GoPay."
                    val created = LanjoNotificationListener.parseAndEnqueue(
                        context = applicationContext,
                        packageName = app,
                        title = title,
                        body = body,
                        requireKnownAppOrKeyword = false
                    )
                    result.success(created?.toString())
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun extractIntentAction(intent: Intent?, notifyFlutter: Boolean) {
        if (intent == null) return
        val action = intent.action ?: return

        var payload: Map<String, Any?>? = null

        if (action == Intent.ACTION_VIEW) {
            val data = intent.data
            if (data != null && data.scheme == "lanjo" && data.host == "route") {
                val path = data.path ?: "/home"
                val query = data.encodedQuery
                val fullRoute = if (query.isNullOrEmpty()) path else "$path?$query"
                payload = mapOf(
                    "kind" to "route",
                    "route" to fullRoute
                )
            }
        } else if (action == Intent.ACTION_SEND) {
            val mime = intent.type ?: ""
            if (mime.startsWith("text/")) {
                val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
                if (!sharedText.isNullOrEmpty()) {
                    payload = mapOf(
                        "kind" to "shared_text",
                        "text" to sharedText
                    )
                }
            } else if (mime.startsWith("image/")) {
                val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                }
                if (uri != null) {
                    val copiedPath = copySharedImageToCache(uri)
                    if (copiedPath != null) {
                        payload = mapOf(
                            "kind" to "shared_image",
                            "path" to copiedPath
                        )
                    }
                }
            }
        } else if (action == Intent.ACTION_PROCESS_TEXT) {
            val selectedText = intent
                .getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
                ?.toString()
                ?.trim()
            if (!selectedText.isNullOrEmpty()) {
                payload = mapOf(
                    "kind" to "shared_text",
                    "text" to selectedText
                )
            }
        }

        if (payload != null) {
            intent.action = Intent.ACTION_MAIN
            if (notifyFlutter && methodChannel != null) {
                methodChannel?.invokeMethod("onNativeAction", payload)
            } else {
                pendingNativeAction = payload
            }
        }
    }

    private fun copySharedImageToCache(uri: Uri): String? {
        return try {
            val input = contentResolver.openInputStream(uri) ?: return null
            val outFile = File(cacheDir, "shared_receipt_${System.currentTimeMillis()}.jpg")
            FileOutputStream(outFile).use { output ->
                input.use { it.copyTo(output) }
            }
            outFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val CHANNEL_NAME = "com.habiboys.lanjo/native"
        private const val REQ_CODE_PERMISSION = 4102
        private var instance: MainActivity? = null

        fun notifySmartInboxUpdated() {
            val act = instance ?: return
            act.runOnUiThread {
                act.methodChannel?.invokeMethod("onSmartInboxUpdated", null)
            }
        }
    }
}
