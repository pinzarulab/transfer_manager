package com.pinzarulab.transfer_manager_android

internal object TransferSecurity {
    private val sensitiveHeaders = setOf(
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
    )

    fun isSensitiveHeader(name: String): Boolean =
        sensitiveHeaders.contains(name.lowercase())
}

