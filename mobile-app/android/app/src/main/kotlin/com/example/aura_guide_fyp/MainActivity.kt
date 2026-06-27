package com.example.aura_guide_fyp

import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.LocaleList
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.aura_guide_fyp/emergency_sound"
    private val flutterPrefsName = "FlutterSharedPreferences"
    private val flutterLanguageKey = "flutter.settings_language"
    private var alertTone: ToneGenerator? = null
    private val alertHandler = Handler(Looper.getMainLooper())
    private var stopToneRunnable: Runnable? = null

    private var englishTts: TextToSpeech? = null
    private val englishTtsReady = AtomicBoolean(false)
    private val englishTtsCallbacks = CopyOnWriteArrayList<(Boolean) -> Unit>()
    private var triedDefaultEngine = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playAlertBeep" -> {
                        val soft = call.argument<Boolean>("soft") ?: false
                        try {
                            playAlertBeep(soft = soft)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("BEEP_FAILED", e.message, null)
                        }
                    }
                    "stopAlertBeep" -> {
                        stopAlertBeep()
                        result.success(null)
                    }
                    "speakEnglishTts" -> {
                        val text = call.argument<String>("text")?.trim().orEmpty()
                        if (text.isEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        speakEnglishTts(text, result)
                    }
                    "stopEnglishTts" -> {
                        englishTts?.stop()
                        result.success(null)
                    }
                    "setAppLocale" -> {
                        val languageTag = call.argument<String>("languageTag")?.trim().orEmpty()
                        if (languageTag.isEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        try {
                            applyAppLocale(languageTag)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("LOCALE_FAILED", e.message, null)
                        }
                    }
                    "release" -> {
                        releaseTone()
                        releaseEnglishTts()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        initEnglishTts()
    }

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(wrapWithStoredAppLocale(newBase))
    }

    override fun onResume() {
        super.onResume()
        readStoredLanguageTag()?.let { applyAppLocale(it) }
    }

    private fun wrapWithStoredAppLocale(base: Context): Context {
        val tag = readStoredLanguageTag(base) ?: return base
        val locale = localeFromTag(tag)
        val config = Configuration(base.resources.configuration)
        config.setLocale(locale)
        return base.createConfigurationContext(config)
    }

    private fun readStoredLanguageTag(base: Context = this): String? {
        val stored = base
            .getSharedPreferences(flutterPrefsName, Context.MODE_PRIVATE)
            .getString(flutterLanguageKey, null)
            ?.trim()
            .orEmpty()
        return stored.ifEmpty { null }
    }

    private var softAlertTone: ToneGenerator? = null

    private fun playAlertBeep(soft: Boolean = false) {
        cancelPendingStopTone()

        if (soft) {
            val tone = softAlertTone ?: ToneGenerator(
                AudioManager.STREAM_NOTIFICATION,
                70,
            ).also { softAlertTone = it }

            tone.startTone(ToneGenerator.TONE_PROP_BEEP, 280)
            val runnable = Runnable {
                stopToneRunnable = null
                try {
                    softAlertTone?.stopTone()
                } catch (_: RuntimeException) {
                }
            }
            stopToneRunnable = runnable
            alertHandler.postDelayed(runnable, 300)
            return
        }

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
        audioManager.setStreamVolume(
            AudioManager.STREAM_ALARM,
            maxVolume,
            0,
        )

        val tone = alertTone ?: ToneGenerator(
            AudioManager.STREAM_ALARM,
            100,
        ).also { alertTone = it }

        tone.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 750)
        val runnable = Runnable {
            stopToneRunnable = null
            try {
                alertTone?.stopTone()
            } catch (_: RuntimeException) {
                // Tone may already have been stopped or released.
            }
        }
        stopToneRunnable = runnable
        alertHandler.postDelayed(runnable, 780)
    }

    private fun stopAlertBeep() {
        cancelPendingStopTone()
        try {
            alertTone?.stopTone()
        } catch (_: RuntimeException) {
            // Ignore if the tone was already stopped or released.
        }
        try {
            softAlertTone?.stopTone()
        } catch (_: RuntimeException) {
        }
    }

    private fun cancelPendingStopTone() {
        stopToneRunnable?.let { alertHandler.removeCallbacks(it) }
        stopToneRunnable = null
    }

    private fun releaseTone() {
        cancelPendingStopTone()
        try {
            alertTone?.release()
        } catch (_: RuntimeException) {
            // Ignore if already released.
        }
        alertTone = null
        try {
            softAlertTone?.release()
        } catch (_: RuntimeException) {
        }
        softAlertTone = null
    }

    /// Align Android/TalkBack app locale with in-app language selection.
    private fun applyAppLocale(languageTag: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getSystemService(LocaleManager::class.java).applicationLocales =
                LocaleList.forLanguageTags(languageTag)
            return
        }

        val locale = localeFromTag(languageTag)
        Locale.setDefault(locale)

        val appResources = applicationContext.resources
        val appConfig = Configuration(appResources.configuration)
        appConfig.setLocale(locale)
        @Suppress("DEPRECATION")
        appResources.updateConfiguration(appConfig, appResources.displayMetrics)

        val activityConfig = Configuration(resources.configuration)
        activityConfig.setLocale(locale)
        @Suppress("DEPRECATION")
        resources.updateConfiguration(activityConfig, resources.displayMetrics)
    }

    private fun localeFromTag(languageTag: String): Locale {
        return when (languageTag.lowercase().replace('_', '-')) {
            "ms", "ms-my" -> Locale("ms", "MY")
            "zh", "zh-cn", "zh-hans" -> Locale.SIMPLIFIED_CHINESE
            "en", "en-us" -> Locale.US
            else -> Locale.forLanguageTag(languageTag)
        }
    }

    private fun releaseEnglishTts() {
        englishTtsCallbacks.clear()
        englishTtsReady.set(false)
        triedDefaultEngine = false
        englishTts?.stop()
        englishTts?.shutdown()
        englishTts = null
    }

    private fun speakEnglishTts(text: String, result: MethodChannel.Result) {
        ensureEnglishTts { ready ->
            if (!ready) {
                result.error(
                    "TTS_INIT_FAILED",
                    "English text-to-speech is not available on this device.",
                    null,
                )
                return@ensureEnglishTts
            }

            val engine = englishTts
            if (engine == null) {
                result.error("TTS_UNAVAILABLE", "English TTS engine missing.", null)
                return@ensureEnglishTts
            }

            engine.stop()
            val utteranceId = "emergency_${System.currentTimeMillis()}"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val spokenId = utteranceId
                engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {}

                    override fun onDone(utteranceId: String?) {
                        if (utteranceId == spokenId) {
                            runOnUiThread { result.success(null) }
                        }
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        runOnUiThread {
                            result.error("TTS_SPEAK_FAILED", "Speech failed.", null)
                        }
                    }

                    override fun onError(utteranceId: String?, errorCode: Int) {
                        runOnUiThread {
                            result.error("TTS_SPEAK_FAILED", "Speech failed.", null)
                        }
                    }
                })

                val params = Bundle()
                params.putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_MUSIC)
                params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
                engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
            } else {
                @Suppress("DEPRECATION")
                engine.speak(text, TextToSpeech.QUEUE_FLUSH, null)
            }

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
                val words = text.split(Regex("\\s+")).filter { it.isNotEmpty() }.size
                val delayMs = (1800L + words * 420L).coerceAtMost(12000L)
                Handler(Looper.getMainLooper()).postDelayed({
                    result.success(null)
                }, delayMs)
            }
        }
    }

    private fun ensureEnglishTts(onReady: (Boolean) -> Unit) {
        if (englishTtsReady.get()) {
            onReady(true)
            return
        }

        englishTtsCallbacks.add(onReady)
        if (englishTts == null) {
            initEnglishTts()
        }
    }

    private fun initEnglishTts() {
        if (englishTts != null) return

        englishTts = TextToSpeech(this, { status ->
            if (status == TextToSpeech.SUCCESS) {
                onEnglishTtsReady()
                return@TextToSpeech
            }

            if (!triedDefaultEngine) {
                triedDefaultEngine = true
                englishTts?.shutdown()
                englishTts = TextToSpeech(this) { retryStatus ->
                    if (retryStatus == TextToSpeech.SUCCESS) {
                        onEnglishTtsReady()
                    } else {
                        finishEnglishTtsInit(false)
                    }
                }
            } else {
                finishEnglishTtsInit(false)
            }
        }, GOOGLE_TTS_ENGINE)
    }

    private fun onEnglishTtsReady() {
        val engine = englishTts ?: run {
            finishEnglishTtsInit(false)
            return
        }

        if (!configureEnglishVoice(engine)) {
            finishEnglishTtsInit(false)
            return
        }

        finishEnglishTtsInit(true)
    }

    private fun finishEnglishTtsInit(success: Boolean) {
        englishTtsReady.set(success)
        val callbacks = englishTtsCallbacks.toList()
        englishTtsCallbacks.clear()
        callbacks.forEach { it(success) }
    }

    private fun configureEnglishVoice(tts: TextToSpeech): Boolean {
        tts.setSpeechRate(0.82f)
        tts.setPitch(1.05f)

        val locales = listOf(Locale.US, Locale.UK, Locale.ENGLISH)
        var languageApplied = false
        for (locale in locales) {
            when (tts.setLanguage(locale)) {
                TextToSpeech.LANG_AVAILABLE,
                TextToSpeech.LANG_COUNTRY_AVAILABLE,
                TextToSpeech.LANG_COUNTRY_VAR_AVAILABLE,
                -> {
                    languageApplied = true
                    break
                }
            }
        }
        if (!languageApplied) return false

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val voices = tts.voices ?: emptySet()
            val englishVoice = voices
                .filter(::isUsableEnglishVoice)
                .sortedWith(
                    compareBy<Voice>(
                        { voiceScore(it) },
                        { it.name },
                    ),
                )
                .firstOrNull()
            if (englishVoice != null) {
                tts.voice = englishVoice
                tts.setLanguage(englishVoice.locale)
            }
        }

        return true
    }

    private fun isUsableEnglishVoice(voice: Voice): Boolean {
        val localeTag = voice.locale.toString().lowercase()
        val name = voice.name.lowercase()
        if (!voice.locale.language.equals("en", ignoreCase = true)) return false
        if (localeTag.startsWith("pt") || name.contains("pt-") || name.contains("por")) {
            return false
        }
        return true
    }

    private fun voiceScore(voice: Voice): Int {
        val localeTag = voice.locale.toString().lowercase().replace('_', '-')
        val name = voice.name.lowercase()
        var score = 0
        if (localeTag == "en-us") score += 100
        if (localeTag == "en-gb") score += 80
        if (localeTag.startsWith("en")) score += 40
        if (name.contains("en-us")) score += 20
        if (name.contains("local")) score += 10
        if (voice.quality >= Voice.QUALITY_HIGH) score += 5
        return score
    }

    override fun onDestroy() {
        releaseTone()
        releaseEnglishTts()
        super.onDestroy()
    }

    companion object {
        private const val GOOGLE_TTS_ENGINE = "com.google.android.tts"
    }
}
