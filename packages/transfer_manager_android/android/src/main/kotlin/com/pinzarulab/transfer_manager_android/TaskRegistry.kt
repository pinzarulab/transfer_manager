package com.pinzarulab.transfer_manager_android

import android.content.Context
import java.util.UUID

internal class TaskRegistry(context: Context) {
    private val preferences =
        context.getSharedPreferences("transfer_manager_tasks", Context.MODE_PRIVATE)

    fun put(taskId: String, workId: UUID) {
        preferences.edit().putString(taskId, workId.toString()).apply()
    }

    fun get(taskId: String): UUID? =
        preferences.getString(taskId, null)?.let {
            runCatching { UUID.fromString(it) }.getOrNull()
        }

    fun entries(): Map<String, UUID> =
        preferences.all.mapNotNull { (taskId, value) ->
            val id = (value as? String)?.let {
                runCatching { UUID.fromString(it) }.getOrNull()
            }
            id?.let { taskId to it }
        }.toMap()

    fun remove(taskId: String) {
        preferences.edit().remove(taskId).apply()
    }
}

