package com.example.himatch

import org.junit.Assert.assertEquals
import org.junit.Test

class MainActivityTest {
    @Test
    fun welcomeMessageUsesProductName() {
        assertEquals("アイマノ", welcomeMessage())
    }
}
