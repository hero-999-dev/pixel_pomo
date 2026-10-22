# 💡 Pixel Pomo — fikir ve yol haritası notları

Henüz yapılmamış öneriler. Bir madde yapıldığında buradan silinir ya da
yanına sürüm numarası yazılır.

## 🌱 Oyun / bahçe
- **Çiçek büyüme aşamaları** — tohum → filiz → çiçek; seans tamamladıkça büyür.
- **Böcekler ödül olsun** — nadir böcekler (ateş böceği, gece kelebeği), bir
  "böcek koleksiyonu" albümü; bazı çiçekler belirli böcekleri çeker.
- **Gece/gündüz + hava durumu** — saate göre ışık; yağmurda böcek gelmez.
- **Seri bonusu** — art arda günlerde ekstra coin; seri kırılınca solan çiçek.
- **Başarımlar** — "100 seans", "ilk bina", "tüm türler" vb.

## ⏱️ Verimlilik
- **Uzun mola** — her 4 seansta bir uzun mola (klasik Pomodoro).
- **Görev listesi** — etikete bağlı basit yapılacaklar; seans bir göreve bağlanır.
- **Ana ekran widget'ı** — kalan süre + bugünkü toplam.
- **Haftalık hedef** — etiket başına hedef saat ve ilerleme çubuğu.

## 💰 Para takibi (sonraki adımlar)
- **Tekrarlayan kayıtlar** — kira, maaş, abonelikler her ay kendiliğinden eklensin.
- **Kategori bütçeleri** — "yemek için ayda X" ve aşınca uyarı.
- **CSV dışa aktarma** — kayıtları tabloya almak için.
- **Hiç kayıt girilmeyen gün** — günlük bütçe coin'i şu an hiç harcama girilmeyen
  güne de veriliyor; bunun ödül olup olmayacağına karar verilmeli.

## 🔧 Teknik
- **`main.dart`'ı bölmek** — ekran başına bir dosya (stats, shop, settings,
  habits, money); şu an ~6.000 satır.
- **Böcek mantığını tek kaynağa almak** — Dart (`garden_engine.dart`) ve Kotlin
  (`GardenRenderer.kt`) elle aynı tutuluyor; ortak sabitler ya da ikisini
  karşılaştıran bir test.
- **Yedekleme** — verileri JSON olarak dışa/içe aktarma; telefon değişince
  geçmiş kaybolmasın.
- **CI'da dal testi** — testler `main` dışındaki dallarda ve PR'larda da
  çalışsın; Kotlin dosyası şu an yalnızca APK üretiminde derleniyor.
