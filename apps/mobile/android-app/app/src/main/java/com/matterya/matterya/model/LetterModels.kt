package com.matterya.matterya.model

import java.util.UUID

data class LetterFlightEvent(
    val id: String = UUID.randomUUID().toString(),
    val threadId: String,
    val body: String,
    val slotUsed: Int,
    val dailyLimit: Int,
    val destinationCountryCode: String,
    val destinationCountryName: String,
)
