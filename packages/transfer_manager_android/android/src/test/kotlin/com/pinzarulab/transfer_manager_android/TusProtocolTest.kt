package com.pinzarulab.transfer_manager_android

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TusProtocolTest {
    @Test
    fun identifiesStatusesThatCanBeRetried() {
        assertTrue(TusProtocol.isRetryableStatus(408))
        assertTrue(TusProtocol.isRetryableStatus(409))
        assertTrue(TusProtocol.isRetryableStatus(423))
        assertTrue(TusProtocol.isRetryableStatus(429))
        assertTrue(TusProtocol.isRetryableStatus(503))
        assertFalse(TusProtocol.isRetryableStatus(400))
        assertFalse(TusProtocol.isRetryableStatus(404))
    }
}
