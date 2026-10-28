# Automatyzacja

[← Spis treści](README.md)

ClipRecorder obsługuje adresy `cliprecorder://`. Każdy program, który potrafi otworzyć adres URL, może więc sterować
nagrywaniem: aplikacja Skróty, Stream Deck, Raycast, Alfred, Keyboard Maestro, BetterTouchTool, skrypty w Terminalu.

## Dostępne akcje

| Adres | Działanie |
|---|---|
| `cliprecorder://save` | zapisuje ostatnie N s (jak <kbd>⌃</kbd><kbd>⌥</kbd><kbd>S</kbd>) |
| `cliprecorder://record` | zaczyna klip, a gdy trwa, kończy go (jak <kbd>⌃</kbd><kbd>⌥</kbd><kbd>R</kbd>). Alias: `toggle` |
| `cliprecorder://stop` | kończy klip, jeśli trwa. W przeciwnym razie nic nie robi |
| `cliprecorder://marker` | dodaje znacznik (jak <kbd>⌃</kbd><kbd>⌥</kbd><kbd>M</kbd>) |
| `cliprecorder://pause` | wstrzymuje nagrywanie w tle albo je wznawia |
| `cliprecorder://resume` | wznawia, jeśli było wstrzymane |
| `cliprecorder://open-last` | otwiera ostatni klip |
| `cliprecorder://settings` | otwiera ustawienia |

Jeśli aplikacja nie działa, otwarcie adresu ją uruchomi. Najczęstsze adresy są też w
*Ustawienia → Skróty → Automatyzacja*, a kliknięcie adresu go kopiuje.

> `stop` i `resume` przydają się w automatyzacjach, bo w przeciwieństwie do `record` i `pause` nie przełączają stanu.
> Dwukrotne wywołanie `stop` nie zacznie nowego klipu.

## Terminal i skrypty

```sh
open cliprecorder://save
open cliprecorder://record   # start…
sleep 30
open cliprecorder://stop     # …i koniec po 30 s
```

## Aplikacja Skróty

1. Utwórz nowy skrót.
2. Dodaj akcję **Otwórz adresy URL** i wpisz np. `cliprecorder://save`.
3. Opcjonalnie: w szczegółach skrótu **Dodaj skrót klawiszowy**, przypnij go do paska menu albo dodaj do
   automatyzacji, np. „gdy otworzę aplikację X → `cliprecorder://resume`”.

Przykład: skrót „Nie nagrywaj prezentacji”, który przy połączeniu z projektorem wywołuje `cliprecorder://pause`.

## Stream Deck

Użyj akcji **System → Website** (albo **Open**) i wpisz adres, np. `cliprecorder://save`.
Wyłącz opcję *GET request in background*, żeby adres otworzył się w systemie, a nie jako zapytanie HTTP.

Popularny układ: jeden przycisk `save`, jeden `record`, jeden `marker`.

## Raycast i Alfred

- **Raycast:** *Create Quicklink* z adresem `cliprecorder://save` i nazwą „Zapisz klip”.
- **Alfred:** *Workflows → Templates → Web → Open URL* albo *Web Search* z adresem `cliprecorder://save`.

## Keyboard Maestro i BetterTouchTool

Akcja **Open URL** z dowolnym adresem z tabeli. Działa też z gestami, przyciskami myszy czy pilotem.
