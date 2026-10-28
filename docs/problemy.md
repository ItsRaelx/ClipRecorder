# Rozwiązywanie problemów

[← Spis treści](README.md)

## Uprawnienia

### Aplikacja pokazuje „Potrzebny dostęp”, choć uprawnienie jest włączone

macOS stosuje uprawnienie do nagrywania ekranu dopiero po ponownym uruchomieniu aplikacji. Kliknij
**Uruchom ponownie** na karcie w popoverze.

Jeśli to nie pomoże (zwykle po przebudowaniu aplikacji z innym podpisem), zresetuj stare wpisy i nadaj
uprawnienia od nowa:

```sh
tccutil reset ScreenCapture io.github.itsraelx.ClipRecorder
tccutil reset Microphone io.github.itsraelx.ClipRecorder
```

### Po każdej aktualizacji trzeba znowu nadawać uprawnienia

Tak działają wydania testowe podpisane ad-hoc: macOS traktuje każdą wersję jak nową aplikację. Przy budowaniu ze
źródeł `build.sh` używa stałego, lokalnego certyfikatu i tego problemu nie ma ([Instalacja](instalacja.md#podpis-przy-budowaniu)).

### macOS co jakiś czas pyta, czy aplikacja dalej może nagrywać ekran

To przypomnienie systemu (od macOS 15) dla wszystkich aplikacji, które nagrywają ekran. Wybierz **Zezwalaj dalej**.

## ClipRecorder chce użyć poufnych informacji

Po zalogowaniu na clip.secc.me token jest w pęku kluczy. Aplikacja zbudowana ze źródeł z lokalnym certyfikatem
dostaje po każdej kompilacji nowy „odcisk”, więc macOS pyta o zgodę ponownie. Wybierz **Zawsze pozwalaj**.
Wydania podpisane certyfikatem Developer ID tego nie robią.

Jeśli okno pojawi się, gdy Mac jest zablokowany, i nie zdążysz odpowiedzieć, aplikacja **nie wyloguje Cię**.
Po prostu spróbuje ponownie później.

## Skróty

### Skrót nic nie robi

- W *Ustawienia → Skróty* sprawdź, czy przy skrócie nie ma napisu **Zajęty przez inną aplikację**. Jeśli jest,
  ustaw inny.
- Gdy nagrywanie w tle jest wstrzymane albo trwa uruchamianie, skróty zapisu nie mają czego zapisać.
  Ikona w pasku menu pokazuje stan.
- **Znacznik** działa tylko w trakcie nagrywania klipu.

### Nie mogę ustawić skrótu bez ⌃ / ⌘

Celowo: skróty z samym <kbd>⌥</kbd> albo <kbd>⇧</kbd> zabierałyby polskie znaki i wielkie litery w każdej
aplikacji. Użyj <kbd>⌃</kbd>, <kbd>⌘</kbd>, połączenia <kbd>⌥</kbd><kbd>⇧</kbd> albo samego klawisza funkcyjnego
(<kbd>F13</kbd>–<kbd>F20</kbd> są zwykle wolne).

## Dźwięk

### W klipie nie ma dźwięku komputera albo mikrofonu

- Sprawdź przełączniki **On/Off** w popoverze. Paski poziomu obok powinny się ruszać.
- Mikrofon wymaga uprawnienia *Mikrofon* w *Ustawieniach systemowych → Prywatność i ochrona*.
- Zwykły odtwarzacz gra ścieżkę *Miks*. Jeśli jedno ze źródeł jest za ciche, zmień proporcje w
  [Ustawieniach → Dźwięk](ustawienia.md#dźwięk).

### Muzyka w AirPodsach gra gorzej, gdy działa ClipRecorder

Nagrywanie z mikrofonu słuchawek Bluetooth przełącza je w tryb rozmowy. Ustaw **Który mikrofon → Automatycznie**:
aplikacja wybierze wtedy mikrofon wbudowany albo na kablu. Popover ostrzega, gdy wybrany mikrofon jest na Bluetooth.

### Mikrofon słuchawek (8/16 kHz) i klip się nie zapisuje

Poprawione w aktualnej wersji: dźwięk jest zawsze zapisywany w 48 kHz, niezależnie od mikrofonu.
Zaktualizuj aplikację.

## Zapis i dysk

### „Za mało miejsca na dysku, żeby zapisać klip”

Aplikacja nie zapisze klipu, gdy na dysku z folderem klipów zostało mniej niż 300 MB, a poniżej 3 GB ostrzega.
Zwolnij miejsce albo włącz automatyczne sprzątanie w [Ustawieniach → Ogólne](ustawienia.md#ogólne).

### Bufor 5 / 10 minut a dysk SSD

Długi bufor to ciągły zapis na dysk, rzędu 100–300 MB na minutę, nadpisywany w kółko. Współczesne dyski SSD
spokojnie to wytrzymują, ale jeśli zależy Ci na minimalnym zużyciu, wybierz bufor do 2 minut (trzymany w pamięci).

### Aplikacja padła w trakcie nagrywania

Klip zapisuje się w częściach co 5 sekund, więc plik w folderze klipów da się odtworzyć do ostatniej zapisanej
części. Przy normalnym zamykaniu aplikacja najpierw kończy i zapisuje klip.

### Klip ma przerwę albo „zamrożony” obraz

Gdy na ekranie nic się nie zmienia, macOS nie wysyła nowych klatek, więc klip pokazuje wtedy ten sam obraz.
To normalne i oszczędza miejsce. Przy zablokowanym ekranie nagrywanie jest wstrzymywane
([więcej](wstrzymywanie.md#blokada-ekranu-i-uśpienie)).

## Udostępnianie

### „Klip jest za duży na Twój plan”

Plan ma limit rozmiaru pojedynczego klipu. Przytnij klip ✂︎ i udostępnij go ponownie albo zmień plan
(*Ustawienia → Konto → Plany…*).

### Wysyłanie przerywa się albo trwa bardzo długo

Komunikat błędu mówi, co się stało: brak internetu, przekroczony czas albo problem z certyfikatem. Wysyłkę
można anulować (✕ przy pasku postępu) i ponowić. Niedokończone wysyłki są sprzątane na serwerze automatycznie.

### Link pokazuje starszą wersję klipu

Po przycięciu klipu link prowadzi do wersji sprzed przycięcia. Aplikacja go wtedy „zapomina”, więc kliknij
**Udostępnij link** jeszcze raz.

## Inne

### Gdzie są logi?

Aplikacja pisze do logu systemowego:

```sh
log stream --predicate 'process == "ClipRecorder"' --level info
```

### Jak zgłosić błąd?

Załóż [zgłoszenie na GitHubie](https://github.com/ItsRaelx/ClipRecorder/issues). Dopisz wersję macOS, wersję
aplikacji (*Ustawienia*, lewy dolny róg) i fragment logu.
