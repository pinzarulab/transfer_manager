package com.pinzarulab.transfer_manager_android

import android.content.Context

internal class TransferPauseStore(context: Context) {
    private val preferences = context.getSharedPreferences(
        "transfer_manager_pause_state",
        Context.MODE_PRIVATE,
    )

    fun isPaused(taskId: String): Boolean = preferences.getBoolean(taskId, false)

    fun setPaused(taskId: String, paused: Boolean) {
        preferences.edit().putBoolean(taskId, paused).commit()
    }

    fun clear(taskId: String) {
        preferences.edit().remove(taskId).commit()
    }
}
