package com.pixelpomo.app

/**
 * A 2D pixel-art flower sold in the shop and (later) planted in the garden. [grid] is a
 * small char map drawn by `PixelArt`: `P`=petal/body, `C`=center/bud, `S`=stem, `L`=leaf,
 * `.`=empty. Colors are `0xAARRGGBB` ints kept here (no `android.graphics`) so this file
 * stays JVM-testable. Names are Turkish for now (localized later with the language work).
 */
data class Flower(
    val id: String,
    val nameTr: String,
    val petal: Int,
    val center: Int,
    val grid: List<String>
)

object Flowers {
    val GREEN = 0xFF46A03C.toInt()   // stems + leaves (and cactus body uses it as petal)

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

    private fun f(id: String, name: String, petal: Long, center: Long, grid: List<String>) =
        Flower(id, name, petal.toInt(), center.toInt(), grid)

    /** The ten starter flowers, in shop order. */
    val ALL = listOf(
        f("gul",       "Gül",       0xFFE5484D, 0xFFB01030, BLOOM),
        f("papatya",   "Papatya",   0xFFFFFFFF, 0xFFF2C94C, BLOOM),
        f("lale",      "Lale",      0xFFE0457B, 0xFFC02060, TULIP),
        f("kaktus",    "Kaktüs",    0xFF46A03C, 0xFFF2C94C, CACTUS),
        f("kasimpati", "Kasımpatı", 0xFFF2994A, 0xFFC9710B, BLOOM),
        f("menekse",   "Menekşe",   0xFF8E4FE0, 0xFFF2C94C, BLOOM),
        f("nilufer",   "Nilüfer",   0xFFF4A6C0, 0xFFF2C94C, BLOOM),
        f("orkide",    "Orkide",    0xFFC24FE0, 0xFF7A2EA0, BLOOM),
        f("begonya",   "Begonya",   0xFFF2585B, 0xFFFFD9A0, BLOOM),
        f("kamelya",   "Kamelya",   0xFFE02C6D, 0xFFFFFFFF, BLOOM)
    )

    fun byId(id: String?): Flower? = ALL.firstOrNull { it.id == id }
}
