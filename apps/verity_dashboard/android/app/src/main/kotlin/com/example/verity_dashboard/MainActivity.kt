package com.example.verity_dashboard

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Base64
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.DataInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.KeyStore
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import javax.crypto.Cipher
import javax.crypto.CipherInputStream
import javax.crypto.CipherOutputStream
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/** Android Storage Access Framework archive bridge, scoped to a user-selected phone folder.
 * An archived SQLite snapshot is encrypted using an independently recoverable password.
 * Keystore only wraps the local automatic-backup password; it never is the sole recovery key.
 */
class MainActivity : FlutterActivity() {
    private val requestFolder = 7412
    private val prefs by lazy { getSharedPreferences("local_archive", MODE_PRIVATE) }
    private var pendingFolder: MethodChannel.Result? = null
    private val random = SecureRandom()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "verity_dashboard/local_backup")
            .setMethodCallHandler { call, result ->
                if (call.method == "chooseFolder") {
                    if (pendingFolder != null) {
                        result.error("BUSY", "Folder chooser already open", null)
                    } else {
                        pendingFolder = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        try { startActivityForResult(intent, requestFolder) }
                        catch (e: Exception) {
                            pendingFolder = null
                            result.error("FOLDER", e.message, null)
                        }
                    }
                    return@setMethodCallHandler
                }
                // PBKDF2 + multi-MB archive I/O must run off the Android UI thread.
                Thread {
                    try {
                        val value: Any? = when (call.method) {
                            "folderStatus" -> currentFolder()?.toString()
                            "hasSecret" -> loadSecret() != null
                            "saveSecret" -> {
                                val secret = call.argument<String>("password")
                                    ?: error("Recovery password required")
                                require(secret.length >= 8) { "Password must have 8 or more characters" }
                                saveSecret(secret)
                                true
                            }
                            "backup" -> {
                                val path = call.argument<String>("snapshotPath")
                                    ?: error("Missing database snapshot")
                                saveArchive(
                                    currentFolder() ?: error("Select a backup folder first"),
                                    File(path),
                                    loadSecret() ?: error("Set a recovery password first")
                                )
                            }
                            "restore" -> {
                                val path = call.argument<String>("destinationPath")
                                    ?: error("Missing restore destination")
                                val password = call.argument<String>("password")
                                    ?: error("Enter your original backup password")
                                restoreArchive(
                                    currentFolder() ?: error("Select the original backup folder"),
                                    File(path), password
                                )
                            }
                            else -> error("Unsupported method: " + call.method)
                        }
                        result.success(value)
                    } catch (e: Exception) {
                        result.error("ARCHIVE", e.message ?: e.javaClass.simpleName, null)
                    }
                }.start()
            }
    }

    @Deprecated("Android SAF folder activity result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != requestFolder) return
        val reply = pendingFolder ?: return
        pendingFolder = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            reply.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            prefs.edit().putString("folder", uri.toString()).apply()
            reply.success(uri.toString())
        } catch (e: Exception) {
            reply.error("FOLDER", e.message, null)
        }
    }

    private fun currentFolder(): Uri? {
        val uri = prefs.getString("folder", null)?.let(Uri::parse) ?: return null
        val permitted = contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission && it.isWritePermission
        }
        return if (permitted) uri else null
    }

    private fun wrappingKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey("verity_archive_wrapping", null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                "verity_archive_wrapping",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private fun saveSecret(password: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey())
        prefs.edit()
            .putString("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString(
                "secret", Base64.encodeToString(
                    cipher.doFinal(password.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP
                )
            )
            .apply()
    }

    private fun loadSecret(): String? {
        val iv = prefs.getString("iv", null) ?: return null
        val encrypted = prefs.getString("secret", null) ?: return null
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE, wrappingKey(),
                GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP))
            )
            String(cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP)), Charsets.UTF_8)
        } catch (_: Exception) { null }
    }

    private fun derive(password: String, salt: ByteArray): SecretKey {
        val spec = PBEKeySpec(password.toCharArray(), salt, 210000, 256)
        return try {
            SecretKeySpec(
                SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                    .generateSecret(spec).encoded,
                "AES"
            )
        } finally { spec.clearPassword() }
    }

    private data class Archive(val id: String, val name: String)

    private fun childList(folder: Uri): List<Archive> {
        val uri = DocumentsContract.buildChildDocumentsUriUsingTree(
            folder, DocumentsContract.getTreeDocumentId(folder)
        )
        val result = mutableListOf<Archive>()
        contentResolver.query(
            uri, arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            ), null, null, null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(1)
                if (name.startsWith("verity-") && name.endsWith(".vbak"))
                    result.add(Archive(cursor.getString(0), name))
            }
        }
        return result.sortedByDescending { it.name }
    }

    private fun docUri(folder: Uri, id: String) =
        DocumentsContract.buildDocumentUriUsingTree(folder, id)

    private fun saveArchive(folder: Uri, source: File, password: String): String {
        require(source.isFile && source.length() > 0) { "SQLite snapshot is missing" }
        val name = "verity-" +
            SimpleDateFormat("yyyyMMdd-HHmmss-SSS", Locale.US).format(Date()) + ".vbak"
        val root = docUri(folder, DocumentsContract.getTreeDocumentId(folder))
        val partial = DocumentsContract.createDocument(
            contentResolver, root, "application/octet-stream", name + ".partial"
        ) ?: error("Could not create backup file")
        var complete = false
        try {
            val salt = ByteArray(16).also(random::nextBytes)
            val nonce = ByteArray(12).also(random::nextBytes)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, derive(password, salt), GCMParameterSpec(128, nonce))
            contentResolver.openOutputStream(partial, "w")?.use { out ->
                out.write("VDBK1".toByteArray(Charsets.US_ASCII))
                out.write(salt)
                out.write(nonce)
                CipherOutputStream(out, cipher).use { encrypted ->
                    FileInputStream(source).use { input -> input.copyTo(encrypted, 65536) }
                }
            } ?: error("Could not write backup")
            DocumentsContract.renameDocument(contentResolver, partial, name)
                ?: error("Could not finalize backup filename")
            complete = true
            // Never delete previous backups until a newly completed one exists.
            childList(folder).drop(2).forEach { old ->
                try { DocumentsContract.deleteDocument(contentResolver, docUri(folder, old.id)) }
                catch (_: Exception) {}
            }
            return name
        } finally {
            if (!complete) {
                try { DocumentsContract.deleteDocument(contentResolver, partial) }
                catch (_: Exception) {}
            }
        }
    }

    private fun restoreArchive(folder: Uri, target: File, password: String): String {
        val latest = childList(folder).firstOrNull()
            ?: error("No completed backups found in this folder")
        target.parentFile?.mkdirs()
        try {
            contentResolver.openInputStream(docUri(folder, latest.id))?.use { raw ->
                val input = DataInputStream(raw)
                val header = ByteArray(5).also(input::readFully)
                require(String(header, Charsets.US_ASCII) == "VDBK1") {
                    "Unsupported backup format"
                }
                val salt = ByteArray(16).also(input::readFully)
                val nonce = ByteArray(12).also(input::readFully)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(
                    Cipher.DECRYPT_MODE, derive(password, salt), GCMParameterSpec(128, nonce)
                )
                // GCM tag verification detects wrong passwords and damaged/truncated backups.
                FileOutputStream(target).use { out ->
                    CipherInputStream(input, cipher).use { decrypted ->
                        decrypted.copyTo(out, 65536)
                    }
                    out.fd.sync()
                }
            } ?: error("Could not open archive")
            require(target.length() > 0) { "Backup is empty" }
            return latest.name
        } catch (e: Exception) {
            target.delete()
            throw e
        }
    }
}
