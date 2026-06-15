// UI strings for the six supported languages (en/tr/pl/de/ko/it). A direct port of the
// Android `values[-xx]/strings.xml` sets. Lookup falls back to English for any missing key.

const Map<String, Map<String, String>> _s = {
  'en': {
    'work': 'WORK', 'break': 'BREAK', 'start': 'START', 'pause': 'PAUSE', 'reset': 'RESET',
    'switchMode': '>> SWITCH MODE', 'session': 'SESSION {0} / {1}', 'allDone': 'ALL DONE!',
    'workDone': 'WORK DONE!', 'breakDone': 'BREAK OVER!',
    'settings': 'SETTINGS', 'theme': 'THEME', 'save': 'SAVE', 'close': 'CLOSE',
    'study': 'STUDY (MIN)', 'breakMin': 'BREAK (MIN)', 'sessions': 'SESSIONS',
    'settingsSaved': 'SETTINGS SAVED', 'language': 'LANGUAGE',
    'label': 'LABEL', 'newLabel': 'NEW LABEL', 'add': 'ADD', 'pickColor': 'PICK A COLOR',
    'removeTitle': 'Remove label?', 'removeMsg': 'Remove the label "{0}"?', 'yes': 'YES', 'no': 'NO',
    'stats': 'STATS', 'today': 'TODAY', 'week': 'THIS WEEK', 'month': 'THIS MONTH',
    'year': 'THIS YEAR', 'all': 'ALL TIME', 'byLabelMonth': 'BY LABEL · {0}',
    'chartBar': 'BAR', 'chartLine': 'LINE', 'chartPie': 'PIE', 'chartNoData': 'No focus minutes this month.',
    'shop': 'SHOP', 'buy': 'BUY', 'owned': 'OWNED {0}', 'notEnough': 'NOT ENOUGH COINS',
    'purchased': 'PURCHASED', 'shopHelp': '1 coin per 5 focus minutes · flowers cost 10',
    'garden': 'GARDEN', 'gardenHelp': 'Tap CUSTOMIZE, then a tile to plant or clear it.',
    'customize': 'CUSTOMIZE', 'done': 'DONE', 'upgrade': 'UPGRADE ({0})', 'maxSize': 'MAX SIZE',
    'gardenSize': '{0} × {1}', 'upgraded': 'GARDEN UPGRADED', 'pickFlower': 'PICK A FLOWER',
    'clearTile': 'CLEAR TILE', 'needFlowers': 'Buy flowers in the SHOP first.',
    'noneLeft': 'None of that flower left to plant.',
  },
  'tr': {
    'work': 'ÇALIŞ', 'break': 'MOLA', 'start': 'BAŞLAT', 'pause': 'DURAKLAT', 'reset': 'SIFIRLA',
    'switchMode': '>> MOD DEĞİŞTİR', 'session': 'SEANS {0} / {1}', 'allDone': 'BİTTİ!',
    'workDone': 'ÇALIŞMA BİTTİ!', 'breakDone': 'MOLA BİTTİ!',
    'settings': 'AYARLAR', 'theme': 'TEMA', 'save': 'KAYDET', 'close': 'KAPAT',
    'study': 'ÇALIŞMA (DK)', 'breakMin': 'MOLA (DK)', 'sessions': 'SEANS',
    'settingsSaved': 'AYARLAR KAYDEDİLDİ', 'language': 'DİL',
    'label': 'ETİKET', 'newLabel': 'YENİ ETİKET', 'add': 'EKLE', 'pickColor': 'RENK SEÇ',
    'removeTitle': 'Etiket silinsin mi?', 'removeMsg': '"{0}" etiketi silinsin mi?', 'yes': 'EVET', 'no': 'HAYIR',
    'stats': 'İSTATİSTİK', 'today': 'BUGÜN', 'week': 'BU HAFTA', 'month': 'BU AY',
    'year': 'BU YIL', 'all': 'TÜM ZAMANLAR', 'byLabelMonth': 'ETİKETE GÖRE · {0}',
    'chartBar': 'ÇUBUK', 'chartLine': 'ÇİZGİ', 'chartPie': 'PASTA', 'chartNoData': 'Bu ay odak dakikası yok.',
    'shop': 'MAĞAZA', 'buy': 'AL', 'owned': 'SAHİP {0}', 'notEnough': 'YETERLİ ALTIN YOK',
    'purchased': 'SATIN ALINDI', 'shopHelp': '5 odak dakikası = 1 altın · çiçek 10',
    'garden': 'BAHÇE', 'gardenHelp': 'ÖZELLEŞTİR\'e dokun, sonra bir kareye dokun.',
    'customize': 'ÖZELLEŞTİR', 'done': 'TAMAM', 'upgrade': 'BÜYÜT ({0})', 'maxSize': 'MAKS BOYUT',
    'gardenSize': '{0} × {1}', 'upgraded': 'BAHÇE BÜYÜTÜLDÜ', 'pickFlower': 'BİR ÇİÇEK SEÇ',
    'clearTile': 'KAREYİ TEMİZLE', 'needFlowers': 'Önce MAĞAZA\'dan çiçek al.',
    'noneLeft': 'Ekecek o çiçekten kalmadı.',
  },
  'pl': {
    'work': 'PRACA', 'break': 'PRZERWA', 'start': 'START', 'pause': 'PAUZA', 'reset': 'RESET',
    'switchMode': '>> ZMIEŃ TRYB', 'session': 'SESJA {0} / {1}', 'allDone': 'GOTOWE!',
    'workDone': 'KONIEC PRACY!', 'breakDone': 'KONIEC PRZERWY!',
    'settings': 'USTAWIENIA', 'theme': 'MOTYW', 'save': 'ZAPISZ', 'close': 'ZAMKNIJ',
    'study': 'PRACA (MIN)', 'breakMin': 'PRZERWA (MIN)', 'sessions': 'SESJE',
    'settingsSaved': 'ZAPISANO', 'language': 'JĘZYK',
    'label': 'ETYKIETA', 'newLabel': 'NOWA ETYKIETA', 'add': 'DODAJ', 'pickColor': 'WYBIERZ KOLOR',
    'removeTitle': 'Usunąć etykietę?', 'removeMsg': 'Usunąć etykietę "{0}"?', 'yes': 'TAK', 'no': 'NIE',
    'stats': 'STATYSTYKI', 'today': 'DZIŚ', 'week': 'TEN TYDZIEŃ', 'month': 'TEN MIESIĄC',
    'year': 'TEN ROK', 'all': 'CAŁY CZAS', 'byLabelMonth': 'WG ETYKIETY · {0}',
    'chartBar': 'SŁUPKI', 'chartLine': 'LINIA', 'chartPie': 'KOŁO', 'chartNoData': 'Brak minut w tym miesiącu.',
    'shop': 'SKLEP', 'buy': 'KUP', 'owned': 'MASZ {0}', 'notEnough': 'ZA MAŁO MONET',
    'purchased': 'KUPIONO', 'shopHelp': '1 moneta za 5 minut · kwiat kosztuje 10',
    'garden': 'OGRÓD', 'gardenHelp': 'Dotknij DOSTOSUJ, potem pole.',
    'customize': 'DOSTOSUJ', 'done': 'GOTOWE', 'upgrade': 'ROZBUDUJ ({0})', 'maxSize': 'MAKS. ROZMIAR',
    'gardenSize': '{0} × {1}', 'upgraded': 'OGRÓD ROZBUDOWANY', 'pickFlower': 'WYBIERZ KWIAT',
    'clearTile': 'WYCZYŚĆ POLE', 'needFlowers': 'Najpierw kup kwiaty w SKLEPIE.',
    'noneLeft': 'Nie masz już tego kwiatu.',
  },
  'de': {
    'work': 'ARBEIT', 'break': 'PAUSE', 'start': 'START', 'pause': 'PAUSE', 'reset': 'ZURÜCK',
    'switchMode': '>> MODUS WECHSELN', 'session': 'RUNDE {0} / {1}', 'allDone': 'FERTIG!',
    'workDone': 'ARBEIT FERTIG!', 'breakDone': 'PAUSE VORBEI!',
    'settings': 'EINSTELLUNGEN', 'theme': 'THEMA', 'save': 'SPEICHERN', 'close': 'SCHLIESSEN',
    'study': 'ARBEIT (MIN)', 'breakMin': 'PAUSE (MIN)', 'sessions': 'RUNDEN',
    'settingsSaved': 'GESPEICHERT', 'language': 'SPRACHE',
    'label': 'LABEL', 'newLabel': 'NEUES LABEL', 'add': 'HINZU', 'pickColor': 'FARBE WÄHLEN',
    'removeTitle': 'Label löschen?', 'removeMsg': 'Label "{0}" löschen?', 'yes': 'JA', 'no': 'NEIN',
    'stats': 'STATISTIK', 'today': 'HEUTE', 'week': 'DIESE WOCHE', 'month': 'DIESER MONAT',
    'year': 'DIESES JAHR', 'all': 'GESAMT', 'byLabelMonth': 'NACH LABEL · {0}',
    'chartBar': 'BALKEN', 'chartLine': 'LINIE', 'chartPie': 'KREIS', 'chartNoData': 'Keine Minuten in diesem Monat.',
    'shop': 'SHOP', 'buy': 'KAUFEN', 'owned': 'BESITZ {0}', 'notEnough': 'ZU WENIG MÜNZEN',
    'purchased': 'GEKAUFT', 'shopHelp': '1 Münze je 5 Minuten · Blume kostet 10',
    'garden': 'GARTEN', 'gardenHelp': 'ANPASSEN tippen, dann ein Feld.',
    'customize': 'ANPASSEN', 'done': 'FERTIG', 'upgrade': 'ERWEITERN ({0})', 'maxSize': 'MAX. GRÖSSE',
    'gardenSize': '{0} × {1}', 'upgraded': 'GARTEN ERWEITERT', 'pickFlower': 'BLUME WÄHLEN',
    'clearTile': 'FELD LEEREN', 'needFlowers': 'Kaufe zuerst Blumen im SHOP.',
    'noneLeft': 'Keine solche Blume mehr übrig.',
  },
  'ko': {
    'work': '집중', 'break': '휴식', 'start': '시작', 'pause': '일시정지', 'reset': '초기화',
    'switchMode': '>> 모드 전환', 'session': '세션 {0} / {1}', 'allDone': '완료!',
    'workDone': '집중 완료!', 'breakDone': '휴식 끝!',
    'settings': '설정', 'theme': '테마', 'save': '저장', 'close': '닫기',
    'study': '집중 (분)', 'breakMin': '휴식 (분)', 'sessions': '세션',
    'settingsSaved': '설정 저장됨', 'language': '언어',
    'label': '라벨', 'newLabel': '새 라벨', 'add': '추가', 'pickColor': '색상 선택',
    'removeTitle': '라벨을 삭제할까요?', 'removeMsg': '"{0}" 라벨을 삭제할까요?', 'yes': '예', 'no': '아니오',
    'stats': '통계', 'today': '오늘', 'week': '이번 주', 'month': '이번 달',
    'year': '올해', 'all': '전체', 'byLabelMonth': '라벨별 · {0}',
    'chartBar': '막대', 'chartLine': '선', 'chartPie': '원형', 'chartNoData': '이번 달 기록이 없습니다.',
    'shop': '상점', 'buy': '구매', 'owned': '보유 {0}', 'notEnough': '코인이 부족합니다',
    'purchased': '구매 완료', 'shopHelp': '5분당 1코인 · 꽃은 10코인',
    'garden': '정원', 'gardenHelp': '꾸미기를 누른 뒤 타일을 누르세요.',
    'customize': '꾸미기', 'done': '완료', 'upgrade': '확장 ({0})', 'maxSize': '최대 크기',
    'gardenSize': '{0} × {1}', 'upgraded': '정원 확장됨', 'pickFlower': '꽃 선택',
    'clearTile': '타일 비우기', 'needFlowers': '먼저 상점에서 꽃을 사세요.',
    'noneLeft': '심을 그 꽃이 없습니다.',
  },
  'it': {
    'work': 'LAVORO', 'break': 'PAUSA', 'start': 'AVVIA', 'pause': 'PAUSA', 'reset': 'AZZERA',
    'switchMode': '>> CAMBIA MODO', 'session': 'SESSIONE {0} / {1}', 'allDone': 'FATTO!',
    'workDone': 'LAVORO FINITO!', 'breakDone': 'PAUSA FINITA!',
    'settings': 'IMPOSTAZIONI', 'theme': 'TEMA', 'save': 'SALVA', 'close': 'CHIUDI',
    'study': 'LAVORO (MIN)', 'breakMin': 'PAUSA (MIN)', 'sessions': 'SESSIONI',
    'settingsSaved': 'SALVATE', 'language': 'LINGUA',
    'label': 'ETICHETTA', 'newLabel': 'NUOVA ETICHETTA', 'add': 'AGGIUNGI', 'pickColor': 'SCEGLI COLORE',
    'removeTitle': 'Eliminare l\'etichetta?', 'removeMsg': 'Eliminare l\'etichetta "{0}"?', 'yes': 'SÌ', 'no': 'NO',
    'stats': 'STATISTICHE', 'today': 'OGGI', 'week': 'QUESTA SETTIMANA', 'month': 'QUESTO MESE',
    'year': 'QUEST\'ANNO', 'all': 'SEMPRE', 'byLabelMonth': 'PER ETICHETTA · {0}',
    'chartBar': 'BARRE', 'chartLine': 'LINEA', 'chartPie': 'TORTA', 'chartNoData': 'Nessun minuto questo mese.',
    'shop': 'NEGOZIO', 'buy': 'COMPRA', 'owned': 'POSSEDUTI {0}', 'notEnough': 'MONETE INSUFFICIENTI',
    'purchased': 'ACQUISTATO', 'shopHelp': '1 moneta ogni 5 minuti · un fiore costa 10',
    'garden': 'GIARDINO', 'gardenHelp': 'Tocca PERSONALIZZA, poi una cella.',
    'customize': 'PERSONALIZZA', 'done': 'FATTO', 'upgrade': 'AMPLIA ({0})', 'maxSize': 'DIM. MAX',
    'gardenSize': '{0} × {1}', 'upgraded': 'GIARDINO AMPLIATO', 'pickFlower': 'SCEGLI UN FIORE',
    'clearTile': 'SVUOTA CELLA', 'needFlowers': 'Compra prima dei fiori nel NEGOZIO.',
    'noneLeft': 'Non hai più quel fiore.',
  },
};

const Map<String, List<String>> _months = {
  'en': ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'],
  'tr': ['OCAK', 'ŞUBAT', 'MART', 'NİSAN', 'MAYIS', 'HAZİRAN', 'TEMMUZ', 'AĞUSTOS', 'EYLÜL', 'EKİM', 'KASIM', 'ARALIK'],
  'pl': ['STYCZEŃ', 'LUTY', 'MARZEC', 'KWIECIEŃ', 'MAJ', 'CZERWIEC', 'LIPIEC', 'SIERPIEŃ', 'WRZESIEŃ', 'PAŹDZIERNIK', 'LISTOPAD', 'GRUDZIEŃ'],
  'de': ['JANUAR', 'FEBRUAR', 'MÄRZ', 'APRIL', 'MAI', 'JUNI', 'JULI', 'AUGUST', 'SEPTEMBER', 'OKTOBER', 'NOVEMBER', 'DEZEMBER'],
  'ko': ['1월', '2월', '3월', '4월', '5월', '6월', '7월', '8월', '9월', '10월', '11월', '12월'],
  'it': ['GENNAIO', 'FEBBRAIO', 'MARZO', 'APRILE', 'MAGGIO', 'GIUGNO', 'LUGLIO', 'AGOSTO', 'SETTEMBRE', 'OTTOBRE', 'NOVEMBRE', 'DICEMBRE'],
};

/// Language tag → display autonym (never translated), in settings order.
const List<List<String>> languageOptions = [
  ['en', 'English'],
  ['tr', 'Türkçe'],
  ['pl', 'Polski'],
  ['de', 'Deutsch'],
  ['ko', '한국어'],
  ['it', 'Italiano'],
];

String t(String lang, String key) => _s[lang]?[key] ?? _s['en']![key] ?? key;

String tf(String lang, String key, List<Object> args) {
  var s = t(lang, key);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', args[i].toString());
  }
  return s;
}

String monthName(String lang, int month1) =>
    (_months[lang] ?? _months['en']!)[month1 - 1];
