package com.pinzarulab.transfer_manager_android

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TransferSecurityTest {
    @Test
    fun `sensitive headers are matched case insensitively`() {
        assertTrue(TransferSecurity.isSensitiveHeader("Authorization"))
        assertTrue(TransferSecurity.isSensitiveHeader("COOKIE"))
        assertFalse(TransferSecurity.isSensitiveHeader("Content-Type"))
    }

    @Test
    fun `retryable server status classification is bounded`() {
        assertTrue(DownloadWorker.isRetryableStatus(408))
        assertTrue(DownloadWorker.isRetryableStatus(429))
        assertTrue(DownloadWorker.isRetryableStatus(503))
        assertFalse(DownloadWorker.isRetryableStatus(404))
    }

    @Test
    fun `public Downloads destinations preserve the file name`() {
        val destination = "transfer-manager-downloads:/report%201.pdf"
        val legacyDestination = "transfer-manager-downloads:report%201.pdf"

        assertTrue(DownloadWorker.isPublicDownloadsDestination(destination))
        assertEquals(
            "report 1.pdf",
            DownloadWorker.publicDownloadFileName(destination),
        )
        assertEquals(
            "report 1.pdf",
            DownloadWorker.publicDownloadFileName(legacyDestination),
        )
        assertNull(
            DownloadWorker.publicDownloadFileName(
                "transfer-manager-downloads:/",
            ),
        )
    }
}
