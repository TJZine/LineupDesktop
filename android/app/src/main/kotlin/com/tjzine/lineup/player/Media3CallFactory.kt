package com.tjzine.lineup.player

import java.io.IOException
import java.io.InterruptedIOException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Request
import okhttp3.Response

/** Owns a response if Media3 abandons its wait for the asynchronous open. */
internal class Media3CallFactory(private val upstream: Call.Factory) : Call.Factory {
    override fun newCall(request: Request): Call = OpeningCall(upstream.newCall(request))

    private class OpeningCall(private val upstream: Call) : Call by upstream {
        private var abandoned = false
        private var delivered: Response? = null

        override fun enqueue(responseCallback: Callback) {
            upstream.enqueue(object : Callback {
                override fun onResponse(call: Call, response: Response) {
                    val handoff = synchronized(this@OpeningCall) {
                        if (abandoned) false else {
                            delivered = response
                            true
                        }
                    }
                    if (handoff) {
                        responseCallback.onResponse(this@OpeningCall, response)
                    } else {
                        response.close()
                        responseCallback.onFailure(this@OpeningCall, InterruptedIOException())
                    }
                }

                override fun onFailure(call: Call, e: IOException) {
                    responseCallback.onFailure(this@OpeningCall, e)
                }
            })
        }

        override fun cancel() {
            // OkHttpDataSource cancels this wrapper when its loader thread gives
            // up waiting for headers. Load retirement cancels the underlying
            // calls directly, leaving any active body read owned by Media3.
            val response = synchronized(this) {
                abandoned = true
                delivered.also { delivered = null }
            }
            upstream.cancel()
            response?.close()
        }

        override fun clone(): Call = OpeningCall(upstream.clone())
    }
}
