# Dokumentacja ClipRecordera

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="screenshots/hero-dark.png">
  <img src="screenshots/hero-light.png" alt="ClipRecorder: popover w pasku menu i podgląd zapisanego klipu">
</picture>

ClipRecorder to aplikacja w pasku menu macOS, która cały czas pamięta ostatnią minutę (albo od 30 s do 10 min)
tego, co dzieje się na ekranie, razem z dźwiękiem komputera i mikrofonem. Gdy wydarzy się coś wartego zapamiętania,
naciskasz skrót i klip zawiera to, co **już minęło**.

## Spis treści

| Strona | O czym |
|---|---|
| [Instalacja](instalacja.md) | pobieranie, budowanie ze źródeł, uprawnienia, aktualizacje, odinstalowanie |
| [Pierwsze kroki](pierwsze-kroki.md) | ikona w pasku menu, popover, szybkie menu, jak działa bufor |
| [Klipy](klipy.md) | zapisywanie i nagrywanie, znaczniki, pasek nagrywania, podgląd, lista klipów, przycinanie, pliki i ścieżki dźwięku |
| [Udostępnianie linkiem](udostepnianie.md) | konto clip.secc.me, logowanie, wysyłanie, widoczność, limity |
| [Wstrzymywanie i energia](wstrzymywanie.md) | pauza na czas, bateria, tryb oszczędzania energii, blokada ekranu |
| [Ustawienia](ustawienia.md) | wszystkie sekcje okna ustawień, opcja po opcji |
| [Automatyzacja](automatyzacja.md) | adresy `cliprecorder://`, aplikacja Skróty, Stream Deck, Terminal, Raycast |
| [Rozwiązywanie problemów](problemy.md) | uprawnienia, pęk kluczy, skróty, dźwięk, miejsce na dysku, FAQ |
| [Dla programistów](dla-programistow.md) | budowa aplikacji, przepływ danych, zrzuty ekranu, wydania |

## W skrócie

| Skrót (domyślnie) | Działanie |
|---|---|
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>R</kbd> | zapisuje ostatnie N s **i nagrywa dalej**, a drugie naciśnięcie kończy klip |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd> | od razu zapisuje **tylko** ostatnie N s |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>M</kbd> | w trakcie nagrywania dodaje znacznik (rozdział w pliku) |

- Klipy trafiają do `~/Movies/Clips` jako pliki `.mov` (wideo HEVC, osobne ścieżki dźwięku).
- Bez logowania aplikacja niczego nie wysyła. Po zalogowaniu na [clip.secc.me](https://clip.secc.me)
  jednym kliknięciem dostajesz link do klipu.
- Wymagania: macOS 15 Sequoia lub nowszy.

## Ograniczenia

- Nagrywany jest jeden ekran albo jedno okno naraz.
- Zmiana źródła, rozdzielczości, płynności lub jakości czyści bufor.
- Bufor 5 / 10 min oznacza ciągły zapis na dysk (rzędu 100–300 MB na minutę, nadpisywany w kółko).
- Interfejs jest tylko po polsku.
