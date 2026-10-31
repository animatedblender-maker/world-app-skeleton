package com.matterya.matterya.data.presence

import com.matterya.matterya.data.graphql.GraphQlClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonPrimitive

/** iOS `PresenceService.swift`. */
class PresenceService(
    private val gql: GraphQlClient = GraphQlClient(),
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var heartbeatJob: Job? = null

    fun startHeartbeat(viewingIso: String?) {
        stopHeartbeat()
        heartbeatJob = scope.launch {
            while (isActive) {
                sendHeartbeat(viewingIso)
                delay(25_000)
            }
        }
    }

    fun stopHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = null
    }

    suspend fun sendHeartbeat(iso: String?) {
        val mutation = """
        mutation Heartbeat(${'$'}iso: String) {
          heartbeat(iso: ${'$'}iso) { ok ttlSeconds lastSeen }
        }
        """.trimIndent()
        val vars = buildMap {
            if (iso != null) put("iso", JsonPrimitive(iso.uppercase()))
        }
        runCatching { gql.request(mutation, vars) }
    }

    suspend fun setOffline() {
        runCatching {
            gql.request("mutation { setOffline }")
        }
    }

    companion object {
        val shared by lazy { PresenceService() }
    }
}
