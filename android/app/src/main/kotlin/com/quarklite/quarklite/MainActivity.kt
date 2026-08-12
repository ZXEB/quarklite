package com.quarklite.quarklite

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.annotation.NonNull
import androidx.core.app.NotificationCompat
import com.gopeed.libgopeed.Libgopeed
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File

open class MainActivity : FlutterActivity() {
    private val GOPEED_CHANNEL = "quarklite.com/gopeed"
    private val SYS_CHANNEL = "quarklite.com/system"
    private val LIVE_CHANNEL = "quarklite.com/live"

    private val LIVE_NOTIF_ID = 9001
    private val LIVE_CHANNEL_ID = "quarklite_live"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val taskQueue =
            flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GOPEED_CHANNEL,
            StandardMethodCodec.INSTANCE,
            taskQueue
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val cfg = call.argument<String>("cfg")
                    try {
                        val port = Libgopeed.start(cfg)
                        result.success(port)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "stop" -> {
                    Libgopeed.stop()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canWriteDownload" -> result.success(canWriteDownload())
                    "openAllFilesAccess" -> {
                        openAllFilesAccess()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LIVE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        try {
                            showLiveUpdate(
                                title = call.argument<String>("title") ?: "",
                                text = call.argument<String>("text") ?: "",
                                done = call.argument<Long>("done") ?: 0L,
                                total = call.argument<Long>("total") ?: 0L,
                                chip = call.argument<String>("chip") ?: "",
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "cancel" -> {
                        cancelLiveUpdate()
                        result.success(null)
                    }
                    "check" -> {
                        try {
                            result.success(checkLiveUpdate())
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ---------------- 实时动态（Live Updates，Android 16+） ----------------

    private fun ensureLiveChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            LIVE_CHANNEL_ID,
            "下载进度",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "下载任务实时进度"
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    @Suppress("DEPRECATION")
    private fun buildLiveUpdateNotification(
        title: String,
        text: String,
        done: Long,
        total: Long,
        chip: String,
    ): Notification {
        ensureLiveChannel()
        val builder = NotificationCompat.Builder(this, LIVE_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_notifications)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        if (Build.VERSION.SDK_INT >= 36) {
            // Android 16+ 实时动态：主屏 / 锁屏 / 状态栏常驻进度
            // 注意：系统要求 EXTRA_COLORIZED=true（setColorized）才具备上屏资格
            builder.setRequestPromotedOngoing(true)
            builder.setColorized(true)
            val style = NotificationCompat.ProgressStyle()
            style.setProgressIndeterminate(total <= 0 || done < 0)
            if (total > 0 && done >= 0) {
                // 用 0..10000 的相对刻度，避免超大文件 int 溢出
                val max = 10000
                val cur = ((done * max) / total).toInt().coerceIn(0, max)
                style.setProgress(cur)
                style.addProgressSegment(
                    NotificationCompat.ProgressStyle.Segment(max)
                        .setColor(Color.parseColor("#3D7BFE"))
                )
                style.setStyledByProgress(true)
            }
            builder.setStyle(style)
            if (chip.isNotBlank()) {
                builder.setShortCriticalText(chip)
            }
        } else {
            // 低版本回退为常驻进度通知
            if (total > 0) {
                val progress = (done * 100 / total).toInt().coerceIn(0, 100)
                builder.setProgress(100, progress, false)
            } else {
                builder.setProgress(0, 0, true)
            }
        }
        return builder.build()
    }

    @Suppress("DEPRECATION")
    private fun showLiveUpdate(
        title: String,
        text: String,
        done: Long,
        total: Long,
        chip: String,
    ) {
        ensureLiveChannel()
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(LIVE_NOTIF_ID, buildLiveUpdateNotification(title, text, done, total, chip))
    }

    private fun cancelLiveUpdate() {
        getSystemService(NotificationManager::class.java).cancel(LIVE_NOTIF_ID)
    }

    /// 诊断实时动态在当前设备/系统上的可用性
    private fun checkLiveUpdate(): Map<String, Any> {
        val nm = getSystemService(NotificationManager::class.java)
        val sdk = Build.VERSION.SDK_INT
        val promotedSupported = sdk >= 36
        val canPost = if (promotedSupported) {
            nm.canPostPromotedNotifications()
        } else {
            false
        }
        var promotable = false
        var promoteReason = ""
        if (promotedSupported) {
            val sample = buildLiveUpdateNotification(
                "下载中 1 个任务  ·  50%",
                "1.0 MB/s  ·  已下载 1.0 GB",
                5000L, 10000L, ""
            )
            promotable = sample.hasPromotableCharacteristics()
            if (!promotable) {
                // 部分内部检查方法为 @hide，用反射读取以便定位原因
                promoteReason = "notification: ongoing=${boolProp(sample, "isOngoingEvent")} " +
                    "title=${boolProp(sample, "hasTitle")} " +
                    "groupSummary=${boolProp(sample, "isGroupSummary")} " +
                    "customView=${boolProp(sample, "containsCustomViews")} " +
                    "colorized=" + sample.extras.getBoolean("android.colorized")
            }
        }
        return mapOf(
            "sdk" to sdk,
            "promotedSupported" to promotedSupported,
            "canPost" to canPost,
            "promotable" to promotable,
            "reason" to promoteReason,
        )
    }

    private fun boolProp(n: Notification, name: String): Boolean {
        return try {
            Notification::class.java.getMethod(name).invoke(n) as Boolean
        } catch (_: Exception) {
            false
        }
    }

    private fun canWriteDownload(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            val dir = File("/storage/emulated/0/Download")
            dir.exists() && dir.canWrite()
        }
    }

    private fun openAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION
                )
                intent.data = Uri.parse("package:$packageName")
                startActivity(intent)
            } catch (e: Exception) {
                startActivity(
                    Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                )
            }
        } else {
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 0)
        }
    }
}
