package com.myoun.anisched

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.FileOutputStream

/**
 * The `anisched/documents` channel (docs/storage.md), Android half.
 *
 * A document is a SAF `content://` URI with a persistable permission — no
 * real path. It is read and written whole, as streams. Every answer is
 * `{status, location?, name?, size?, modifiedMs?, message?}`. Ported from
 * Anicel's `qa_storage` runner.
 */
class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var pendingSource: String? = null

    private val pickRequest = 5101
    private val saveAsRequest = 5102

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "anisched/documents")
            .setMethodCallHandler { call, result ->
                val location = call.argument<String>("location")
                when (call.method) {
                    "pick" -> pick(result)
                    "saveAs" -> saveAs(call.argument("sourcePath"), call.argument("name"), result)
                    "reopen" -> result.success(reopen(location))
                    "stat" -> background(result) { stat(Uri.parse(location!!)) }
                    "readInto" -> background(result) {
                        readInto(Uri.parse(location!!), call.argument<String>("destinationPath")!!)
                        mapOf("status" to "granted")
                    }
                    "replaceFrom" -> background(result) {
                        replaceFrom(Uri.parse(location!!), File(call.argument<String>("sourcePath")!!))
                        mapOf("status" to "granted")
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ---- pickers ----

    private fun pick(result: MethodChannel.Result) {
        if (pending != null) return result.success(mapOf("status" to "cancelled"))
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
            // The type is not one the system knows; Dart checks the content.
            type = "*/*"
        }
        launch(intent, pickRequest, result)
    }

    private fun saveAs(sourcePath: String?, name: String?, result: MethodChannel.Result) {
        if (sourcePath.isNullOrEmpty()) return result.success(unavailable("no source"))
        if (pending != null) return result.success(mapOf("status" to "cancelled"))
        pendingSource = sourcePath
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // An unknown type makes some providers refuse to create at all.
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name ?: File(sourcePath).name)
        }
        launch(intent, saveAsRequest, result)
    }

    @Suppress("DEPRECATION")
    private fun launch(intent: Intent, requestCode: Int, result: MethodChannel.Result) {
        pending = result
        try {
            startActivityForResult(intent, requestCode)
        } catch (error: Exception) {
            pending = null
            pendingSource = null
            result.success(unavailable(error.toString()))
        }
    }

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // First: plugins that open activities (file_selector) answer here too.
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequest && requestCode != saveAsRequest) return
        val waiting = pending ?: return
        pending = null
        val source = pendingSource
        pendingSource = null
        val uri = if (resultCode == RESULT_OK) data?.data else null
        if (uri == null) return waiting.success(mapOf("status" to "cancelled"))
        takePersistable(uri)
        if (requestCode == pickRequest) return waiting.success(describe(uri))
        background(waiting) {
            replaceFrom(uri, File(source!!))
            describe(uri)
        }
    }

    // Keeps the grant across restarts: read and write where the provider
    // gives both, read alone where it does not.
    private fun takePersistable(uri: Uri) {
        val read = Intent.FLAG_GRANT_READ_URI_PERMISSION
        for (flags in listOf(read or Intent.FLAG_GRANT_WRITE_URI_PERMISSION, read)) {
            try {
                contentResolver.takePersistableUriPermission(uri, flags)
                return
            } catch (_: Exception) {
                // Not every provider offers a persistable grant.
            }
        }
    }

    // ---- documents ----

    // The grant lives with the OS; it is either still there or gone.
    private fun reopen(location: String?): Map<String, Any?> {
        if (location == null) return unavailable("no location")
        val uri = Uri.parse(location)
        val held = contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
        return if (held) mapOf("status" to "granted") else unavailable("the grant is gone")
    }

    private fun describe(uri: Uri): Map<String, Any?> {
        var name: String? = null
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) name = it.getString(0) }
        } catch (_: Exception) {
            // A provider that will not answer a query still hands out bytes.
        }
        return mapOf("status" to "granted", "location" to uri.toString(), "name" to name)
    }

    private fun stat(uri: Uri): Map<String, Any?> {
        val columns = arrayOf(OpenableColumns.SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
        return try {
            contentResolver.query(uri, columns, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return mapOf("status" to "missing")
                val answer = mutableMapOf<String, Any?>("status" to "granted")
                val size = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (size >= 0 && !cursor.isNull(size)) answer["size"] = cursor.getLong(size)
                val modified = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                if (modified >= 0 && !cursor.isNull(modified)) answer["modifiedMs"] = cursor.getLong(modified)
                if (answer["size"] == null) answer["size"] = sizeByOpening(uri)
                answer
            } ?: mapOf("status" to "missing")
        } catch (_: FileNotFoundException) {
            mapOf("status" to "missing")
        }
    }

    private fun sizeByOpening(uri: Uri): Long =
        contentResolver.openFileDescriptor(uri, "r")?.use { it.statSize }
            ?: throw FileNotFoundException(uri.toString())

    // Whole copy into a part file, renamed only once complete.
    private fun readInto(uri: Uri, destinationPath: String) {
        val part = File("$destinationPath.part")
        try {
            val input = contentResolver.openInputStream(uri) ?: throw FileNotFoundException(uri.toString())
            input.use { stream -> FileOutputStream(part).use { stream.copyTo(it, 1 shl 20) } }
            if (!part.renameTo(File(destinationPath))) throw java.io.IOException("rename failed")
        } finally {
            part.delete()
        }
    }

    // "wt" first: plain "w" does not truncate on every provider, and a
    // shorter file over a longer one would keep the old tail. The length is
    // cut to what was written wherever the descriptor has one.
    private fun replaceFrom(uri: Uri, source: File) {
        val descriptor = openForReplacing(uri)
        try {
            val output = FileOutputStream(descriptor.fileDescriptor)
            val written = FileInputStream(source).use { it.copyTo(output, 1 shl 20) }
            output.flush()
            try {
                android.system.Os.ftruncate(descriptor.fileDescriptor, written)
            } catch (_: Exception) {
                // A pipe has no length to cut.
            }
        } finally {
            descriptor.close()
        }
    }

    private fun openForReplacing(uri: Uri): ParcelFileDescriptor {
        var refusal: Exception? = null
        for (mode in listOf("wt", "w")) {
            try {
                contentResolver.openFileDescriptor(uri, mode)?.let { return it }
            } catch (error: Exception) {
                refusal = error
            }
        }
        throw refusal ?: FileNotFoundException(uri.toString())
    }

    // ---- plumbing ----

    private fun unavailable(message: String): Map<String, Any?> =
        mapOf("status" to "unavailable", "message" to message)

    // Off the main thread (a provider can take its time), answered on it.
    private fun background(result: MethodChannel.Result, work: () -> Map<String, Any?>) {
        Thread {
            val answer = try {
                work()
            } catch (error: Exception) {
                unavailable(error.toString())
            }
            main.post { result.success(answer) }
        }.start()
    }
}
