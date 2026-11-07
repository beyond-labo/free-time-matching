package com.beyondlabo.aimano

import org.junit.Assert.assertEquals
import org.junit.Test

class MainActivityTest {
    @Test
    fun welcomeMessageUsesProductName() {
        assertEquals("アイマノ", welcomeMessage())
    }
}
