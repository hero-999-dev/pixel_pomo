package com.pixelpomo.app

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * Applies the user-selected UI language. The chosen language tag is stored in
 * [SharedPreferences]; [MainActivity.attachBaseContext] wraps the base context in a config
 * carrying that [Locale], so resource lookups (incl. `values-tr/pl/de/ko/it`) resolve to it
 * regardless of the OS language. Self-contained (no `AppCompatDelegate` locale service), so it
 * behaves identically on every supported API level (minSdk 26).
 */
object LocaleManager {

    /** Supported UI languages as (tag, autonym) — autonyms are intentionally NOT translated. */
    val LANGUAGES = listOf(
        "en" to "English",
        "tr" to "Türkçe",
        "pl" to "Polski",
        "de" to "Deutsch",
        "ko" to "한국어",
        "it" to "Italiano"
    )

    const val DEFAULT = "en"

    fun isSupported(tag: String?): Boolean = LANGUAGES.any { it.first == tag }

    fun autonym(tag: String): String = LANGUAGES.firstOrNull { it.first == tag }?.second ?: tag

    /** Returns a context whose resources resolve in [languageTag]. */
    fun wrap(base: Context, languageTag: String): Context {
        val tag = if (isSupported(languageTag)) languageTag else DEFAULT
        val locale = Locale(tag)
        Locale.setDefault(locale)
        val config = Configuration(base.resources.configuration)
        config.setLocale(locale)
        return base.createConfigurationContext(config)
    }
}
