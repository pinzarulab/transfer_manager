package com.pinzarulab.transfer_manager_android

import android.content.Context

internal class DownloadMetadataStore(context: Context) {
    private val preferences =
        context.getSharedPreferences("transfer_manager_download_metadata", Context.MODE_PRIVATE)

    fun validator(taskId: String): String? =
        preferences.getString("$taskId:validator", null)

    fun putValidator(taskId: String, value: String?) {
        if (value == null) return
        preferences.edit().putString("$taskId:validator", value).apply()
    }

    fun clear(taskId: String) {
        preferences.edit().remove("$taskId:validator").apply()
    }
}

