package com.tjzine.lineup.player

import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class OriginPolicyTest {
    @Test
    fun originalHttpsOriginOnly() {
        val original = "https://localhost:18443/auth/a.mp4".toHttpUrl()
        assertTrue(
            OriginPolicy.sameOrigin(original, "https://localhost:18443/auth/b.mp4".toHttpUrl())
        )
        for (target in
            listOf(
                "https://127.0.0.1:18443/b",
                "https://localhost:18444/b",
                "http://localhost:18443/b",
                "https://user:pass@localhost:18443/b",
                "https://localhost:18443/b?X-Plex-Token=invalid",
            )) {
            assertFalse(OriginPolicy.sameOrigin(original, target.toHttpUrl()))
        }
    }
}
