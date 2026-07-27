package com.pinzarulab.transfer_manager_android

import android.content.Context

internal data class TusUploadSession(
    val uploadUrl: String,
    val offset: Long,
    val sourceLength: Long,
    val sourceModified: Long,
)

internal class TusUploadMetadataStore(context: Context) {
    private val preferences = context.getSharedPreferences(
        "transfer_manager_tus_sessions",
        Context.MODE_PRIVATE,
    )

    fun get(taskId: String): TusUploadSession? {
        val prefix = prefix(taskId)
        val uploadUrl = preferences.getString("${prefix}url", null) ?: return null
        return TusUploadSession(
            uploadUrl = uploadUrl,
            offset = preferences.getLong("${prefix}offset", 0),
            sourceLength = preferences.getLong("${prefix}length", -1),
            sourceModified = preferences.getLong("${prefix}modified", -1),
        )
    }

    fun put(taskId: String, session: TusUploadSession) {
        val prefix = prefix(taskId)
        preferences.edit()
            .putString("${prefix}url", session.uploadUrl)
            .putLong("${prefix}offset", session.offset)
            .putLong("${prefix}length", session.sourceLength)
            .putLong("${prefix}modified", session.sourceModified)
            .commit()
    }

    fun clear(taskId: String) {
        val prefix = prefix(taskId)
        preferences.edit()
            .remove("${prefix}url")
            .remove("${prefix}offset")
            .remove("${prefix}length")
            .remove("${prefix}modified")
            .commit()
    }

    private fun prefix(taskId: String) = "$taskId:"
}
