package com.pinzarulab.transfer_manager_android

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.IOException
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class TransferDurabilityInstrumentedTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val taskId = "instrumented-${UUID.randomUUID()}"

    @After
    fun cleanUp() {
        TransferPauseStore(context).clear(taskId)
        TusUploadMetadataStore(context).clear(taskId)
    }

    @Test
    fun persistedControlAndTusSessionSurviveStoreRecreation() {
        TransferPauseStore(context).setPaused(taskId, true)
        TusUploadMetadataStore(context).put(
            taskId,
            TusUploadSession(
                uploadUrl = "https://example.com/uploads/one",
                offset = 4096,
                sourceLength = 8192,
                sourceModified = 1234,
            ),
        )

        assertTrue(TransferPauseStore(context).isPaused(taskId))
        val restored = TusUploadMetadataStore(context).get(taskId)
        assertEquals("https://example.com/uploads/one", restored?.uploadUrl)
        assertEquals(4096L, restored?.offset)
        assertEquals(8192L, restored?.sourceLength)
    }

    @Test
    fun lowStorageGuardRejectsDownloadBeforeWriting() {
        val destination = File(context.cacheDir, "$taskId.bin")
        val impossibleSize = context.cacheDir.usableSpace
            .let { if (it == Long.MAX_VALUE) it else it + 1 }

        assertThrows(IOException::class.java) {
            TransferStorageGuard.requireDownloadCapacity(
                destination,
                impossibleSize,
            )
        }
    }

    @Test
    fun notificationActionsPersistPauseAndResume() {
        val receiver = TransferNotificationActionReceiver()
        val base = Intent()
            .putExtra(TransferNotificationActionReceiver.EXTRA_TASK_ID, taskId)
            .putExtra(
                TransferNotificationActionReceiver.EXTRA_WORKER_ID,
                UUID.randomUUID().toString(),
            )

        receiver.onReceive(
            context,
            Intent(base).setAction(TransferNotificationActionReceiver.ACTION_PAUSE),
        )
        assertTrue(TransferPauseStore(context).isPaused(taskId))

        receiver.onReceive(
            context,
            Intent(base).setAction(TransferNotificationActionReceiver.ACTION_RESUME),
        )
        assertEquals(false, TransferPauseStore(context).isPaused(taskId))
    }
}
