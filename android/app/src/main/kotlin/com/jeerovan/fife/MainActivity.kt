package com.jeerovan.fife

import android.content.res.Configuration
import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity: FlutterFragmentActivity() {
    private var privacyEnabled = false
    private var resumed = false
    private var privacyCover: View? = null
    private var previousAccessibility: Int? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        privacyEnabled = getSharedPreferences("fife_app_lock", MODE_PRIVATE)
            .getBoolean("privacy_enabled", false)
        updateSecureFlag()
        if (privacyEnabled) conceal()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        if (privacyEnabled) conceal()
    }

    override fun onPause() {
        resumed = false
        if (privacyEnabled) conceal()
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus && privacyEnabled) conceal()
    }

    private fun updateSecureFlag() {
        if (privacyEnabled) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    private fun conceal() {
        if (privacyCover != null) return
        val decor = window.decorView as ViewGroup
        previousAccessibility = decor.importantForAccessibility
        decor.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        val cover = View(this)
        val dark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        cover.setBackgroundColor(if (dark) Color.BLACK else Color.WHITE)
        cover.isClickable = true
        decor.addView(cover, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        privacyCover = cover
    }

    private fun revealSafeFrame() {
        val decor = window.decorView as ViewGroup
        privacyCover?.let { decor.removeView(it) }
        privacyCover = null
        previousAccessibility?.let { decor.importantForAccessibility = it }
        previousAccessibility = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.jeerovan.fife/app_lock_privacy").setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    privacyEnabled = call.arguments == true
                    getSharedPreferences("fife_app_lock", MODE_PRIVATE).edit()
                        .putBoolean("privacy_enabled", privacyEnabled).apply()
                    updateSecureFlag()
                    if (!privacyEnabled) revealSafeFrame()
                    result.success(null)
                }
                "frameReady" -> {
                    if (resumed && hasWindowFocus()) revealSafeFrame()
                    result.success(null)
                }
                "copyRecoveryPhrase" -> {
                    val text = call.arguments as? String
                    if (!privacyEnabled || !resumed || !hasWindowFocus() ||
                        text == null || text.split(" ").size != 24) {
                        result.error("RECOVERY_COPY_UNAVAILABLE", "Protected copy unavailable", null)
                    } else {
                        try {
                            val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                            val token = UUID.randomUUID().toString()
                            val tokenKey = "com.jeerovan.fife.recovery_clip"
                            val clip = ClipData.newPlainText("FiFe recovery phrase", text)
                            clip.description.extras = PersistableBundle().apply {
                                putBoolean("android.content.extra.IS_SENSITIVE", true)
                                putString(tokenKey, token)
                            }
                            clipboard.setPrimaryClip(clip)
                            Handler(Looper.getMainLooper()).postDelayed({
                                // Never erase a subsequent copy, including another app's.
                                try {
                                    if (clipboard.primaryClipDescription?.extras?.getString(tokenKey) == token) {
                                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                            clipboard.clearPrimaryClip()
                                        } else {
                                            clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                                        }
                                    }
                                } catch (_: SecurityException) { /* OS owns background clipboard access. */ }
                            }, 60_000)
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("RECOVERY_COPY_UNAVAILABLE", "Protected copy unavailable", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
