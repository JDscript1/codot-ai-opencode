package org.godotengine.editor

import android.app.ActivityManager
import android.content.Context

/** Refuse the heaviest native workloads when Android reports no safe memory headroom. */
object AIMemoryGuard {
    private const val MEBIBYTE = 1024L * 1024L

    fun ensure(context: Context, requiredMb: Int, operation: String) {
        val activity = context.getSystemService(ActivityManager::class.java) ?: return
        val info = ActivityManager.MemoryInfo()
        activity.getMemoryInfo(info)
        if (info.availMem <= 0) return
        val headroom = (info.availMem - info.threshold).coerceAtLeast(0)
        check(!info.lowMemory && headroom >= requiredMb * MEBIBYTE) {
            "Memorie insuficientă pentru $operation. Sunt necesari aproximativ $requiredMb MB liberi; închide alte aplicații și reîncearcă."
        }
    }
}
