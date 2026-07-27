package com.pinzarulab.transfer_manager_android

import android.util.Base64
import java.nio.charset.StandardCharsets

internal object TusProtocol {
    const val VERSION = "1.0.0"

    fun encodeMetadata(metadata: Map<String, String>): String =
        metadata.entries.joinToString(",") { (key, value) ->
            val encoded = Base64.encodeToString(
                value.toByteArray(StandardCharsets.UTF_8),
                Base64.NO_WRAP,
            )
            "$key $encoded"
        }

    fun isRetryableStatus(status: Int): Boolean =
        status == 408 ||
            status == 409 ||
            status == 423 ||
            status == 429 ||
            status in 500..599
}
