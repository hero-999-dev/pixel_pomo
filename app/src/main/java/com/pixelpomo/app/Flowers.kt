package com.pixelpomo.app

/**
 * A 2D pixel-art flower sold in the shop and planted in the garden. [grid] is a small char
 * map drawn by `PixelArt`: `P`=petal/body, `C`=center/bud, `S`=stem, `L`=leaf, `.`=empty.
 * Colors are `0xAARRGGBB` ints kept here (no `android.graphics`) so this file stays
 * JVM-testable. [names] localizes the flower name across the app's six languages.
 */
data class Flower(
    val id: String,
    val names: Map<String, String>,
    val petal: Int,
    val center: Int,
    val grid: List<String>
) {
    /** Turkish name kept as a convenience (the original catalog language). */
    val nameTr: String get() = names["tr"] ?: names["en"] ?: id

    /** Localized name for [lang] (e.g. "tr", "de"), falling back to English then Turkish. */
    fun nameIn(lang: String): String = names[lang] ?: names["en"] ?: nameTr
}

object Flowers {
    val GREEN = 0xFF46A03C.toInt()   // stems + leaves (and cactus body uses it as petal)

    /** The six supported language codes, in settings order. */
    val LANGS = listOf("en", "tr", "pl", "de", "ko", "it")

    // Three compact 8×8 bloom templates, reused with different palettes for variety.
    private val BLOOM = listOf(
        "..PPP...",
        ".PPPPP..",
        ".PPCPP..",
        ".PPPPP..",
        "..PPP...",
        "...S....",
        "..LSL...",
        "...S...."
    )
    private val TULIP = listOf(
        ".P.P.P..",
        ".PPPPP..",
        ".PPPPP..",
        "..PPP...",
        "...S....",
        "..LS....",
        "...SL...",
        "...S...."
    )
    private val CACTUS = listOf(
        "...C....",
        "..PPP...",
        "P.PPP...",
        "PPPPP...",
        "..PPP...",
        "..PPP...",
        "..PPP...",
        "..PPP..."
    )

    /** Bundle the six localized names for one flower (en, tr, pl, de, ko, it). */
    private fun loc(en: String, tr: String, pl: String, de: String, ko: String, it: String) =
        mapOf("en" to en, "tr" to tr, "pl" to pl, "de" to de, "ko" to ko, "it" to it)

    private fun f(id: String, names: Map<String, String>, petal: Long, center: Long, grid: List<String>) =
        Flower(id, names, petal.toInt(), center.toInt(), grid)

    /** The ten starter flowers, in shop order. */
    val ALL = listOf(
        f("gul",       loc("Rose", "Gül", "Róża", "Rose", "장미", "Rosa"),
            0xFFE5484D, 0xFFB01030, BLOOM),
        f("papatya",   loc("Daisy", "Papatya", "Stokrotka", "Gänseblümchen", "데이지", "Margherita"),
            0xFFFFFFFF, 0xFFF2C94C, BLOOM),
        f("lale",      loc("Tulip", "Lale", "Tulipan", "Tulpe", "튤립", "Tulipano"),
            0xFFE0457B, 0xFFC02060, TULIP),
        f("kaktus",    loc("Cactus", "Kaktüs", "Kaktus", "Kaktus", "선인장", "Cactus"),
            0xFF46A03C, 0xFFF2C94C, CACTUS),
        f("kasimpati", loc("Chrysanthemum", "Kasımpatı", "Chryzantema", "Chrysantheme", "국화", "Crisantemo"),
            0xFFF2994A, 0xFFC9710B, BLOOM),
        f("menekse",   loc("Violet", "Menekşe", "Fiołek", "Veilchen", "제비꽃", "Viola"),
            0xFF8E4FE0, 0xFFF2C94C, BLOOM),
        f("nilufer",   loc("Water Lily", "Nilüfer", "Lilia wodna", "Seerose", "수련", "Ninfea"),
            0xFFF4A6C0, 0xFFF2C94C, BLOOM),
        f("orkide",    loc("Orchid", "Orkide", "Orchidea", "Orchidee", "난초", "Orchidea"),
            0xFFC24FE0, 0xFF7A2EA0, BLOOM),
        f("begonya",   loc("Begonia", "Begonya", "Begonia", "Begonie", "베고니아", "Begonia"),
            0xFFF2585B, 0xFFFFD9A0, BLOOM),
        f("kamelya",   loc("Camellia", "Kamelya", "Kamelia", "Kamelie", "동백", "Camelia"),
            0xFFE02C6D, 0xFFFFFFFF, BLOOM)
    )

    fun byId(id: String?): Flower? = ALL.firstOrNull { it.id == id }
}
