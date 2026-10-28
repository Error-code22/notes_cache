package com.notescache.notes_cache

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var installerChannel: MethodChannel? = null
    private var pendingUri: Uri? = null
    private var pendingName: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "foluma/intents")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPendingDocument" -> takePendingDocument(result)
                else -> result.notImplemented()
            }
        }

        installerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "foluma/installer",
        )
        installerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallPackages" -> result.success(canInstallPackages())
                "openInstallSettings" -> {
                    openInstallSettings()
                    result.success(true)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("missing_path", "No APK path supplied", null)
                    } else {
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error(
                                "install_failed",
                                e.message ?: "Could not open the package installer",
                                null,
                            )
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
            try {
                startActivity(intent)
                return
            } catch (_: Exception) {
                // Some OEM builds hide the per-app screen; fall back to app info.
            }
        }
        startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            ),
        )
    }

    private fun installApk(path: String) {
        val file = File(path)
        require(file.exists()) { "The downloaded APK is missing." }
        require(file.length() > 1_000_000) { "The downloaded APK is incomplete." }

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.foluma.installer",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    // Documents are delivered through our own channel. Letting Flutter's
    // default deep-link handler also treat the file:// URI as a route causes
    // an "unknown route" crash on every warm Open-with share.
    override fun shouldHandleDeeplinking(): Boolean = false

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIntent(intent)
        channel?.invokeMethod("sharedDocumentAvailable", null)
    }

    private fun captureIntent(intent: Intent?) {
        if (intent == null) return
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                }
            }
            else -> null
        } ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri

        if (uri != null) {
            pendingUri = uri
            pendingName = runCatching { displayName(uri) }.getOrNull()
        }
    }

    private fun takePendingDocument(result: MethodChannel.Result) {
        val uri = pendingUri
        if (uri == null) {
            result.success(null)
            return
        }
        pendingUri = null
        val name = pendingName ?: "Shared document"
        pendingName = null

        Thread {
            try {
                val file = copyToCache(uri, name)
                runOnUiThread {
                    result.success(mapOf("path" to file.absolutePath, "name" to name))
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "copy_failed",
                        e.message ?: "Could not read the shared file",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun copyToCache(uri: Uri, originalName: String): File {
        val safeName = sanitizeName(originalName)
        val mime = contentResolver.getType(uri)
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime ?: "")
        val withExtension = if (safeName.contains('.') || extension == null) {
            safeName
        } else {
            "$safeName.$extension"
        }

        val directory = File(cacheDir, "foluma_shared").apply { mkdirs() }
        val destination = File(directory, "${System.currentTimeMillis()}_$withExtension")
        if (uri.scheme == "file") {
            val source = File(uri.path ?: error("Missing file path"))
            source.copyTo(destination, overwrite = true)
        } else {
            contentResolver.openInputStream(uri).use { input ->
                val stream = input ?: error("Could not open the shared file")
                destination.outputStream().use { output -> stream.copyTo(output) }
            }
        }
        return destination
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "content") {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) return cursor.getString(index)
                }
            }
        }
        return uri.lastPathSegment
            ?.substringAfterLast('/')
            ?.takeIf { it.isNotBlank() }
    }

    private fun sanitizeName(name: String): String {
        val cleaned = name
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[^A-Za-z0-9._ -]"), "_")
            .trim()
        return cleaned.ifEmpty { "shared_document" }
    }
}
