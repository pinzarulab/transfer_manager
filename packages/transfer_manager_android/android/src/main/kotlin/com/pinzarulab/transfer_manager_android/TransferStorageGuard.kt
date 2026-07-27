package com.pinzarulab.transfer_manager_android

import java.io.File
import java.io.IOException

internal object TransferStorageGuard {
    private const val RESERVED_BYTES = 1024L * 1024L

    fun requireDownloadCapacity(destination: File, remainingBytes: Long) {
        if (remainingBytes <= 0) return
        val directory = destination.parentFile ?: destination.absoluteFile.parentFile
            ?: throw IOException("Download destination has no parent directory")
        val required = if (remainingBytes > Long.MAX_VALUE - RESERVED_BYTES) {
            Long.MAX_VALUE
        } else {
            remainingBytes + RESERVED_BYTES
        }
        if (directory.usableSpace < required) {
            throw IOException("Insufficient storage for download")
        }
    }
}
