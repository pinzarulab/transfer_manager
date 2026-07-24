package com.pinzarulab.transfer_manager_android

import kotlin.test.Test
import kotlin.test.assertFalse
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
}
