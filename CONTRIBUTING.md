# Jak pomóc

Dzięki, że chcesz pomóc przy ClipRecorderze! Każda pomoc się przydaje: zgłoszenie błędu, pomysł, poprawka
w dokumentacji czy kod.

## Zgłoszenia i pomysły

- **Błąd:** [nowe zgłoszenie → Zgłoś błąd](https://github.com/ItsRaelx/ClipRecorder/issues/new/choose).
  Formularz poprosi o wersję aplikacji, system i kroki do powtórzenia.
- **Pomysł:** [nowe zgłoszenie → Pomysł na funkcję](https://github.com/ItsRaelx/ClipRecorder/issues/new/choose).
- **Pytanie:** [Dyskusje → Q&A](https://github.com/ItsRaelx/ClipRecorder/discussions/categories/q-a).
- **Luka bezpieczeństwa:** wyłącznie prywatnie, zobacz [SECURITY.md](SECURITY.md).

## Struktura repozytorium

| Folder | Zawartość |
|---|---|
| `macos/` | aplikacja na macOS (pakiet Swift) |
| `windows/` | aplikacja na Windowsa (w przygotowaniu, zobacz [windows/README.md](windows/README.md)) |
| `docs/` | dokumentacja dla użytkowników, ze zrzutami ekranu |

Opis architektury aplikacji na macOS: [docs/macos/dla-programistow.md](docs/macos/dla-programistow.md).

## Budowanie (macOS)

Wymagania: macOS 15+, Xcode albo Command Line Tools.

```sh
cd macos
./build.sh            # build/ClipRecorder.app
./build.sh --install  # i od razu do /Applications
```

`build.sh` podpisuje aplikację lokalnym certyfikatem, żeby uprawnienia do nagrywania ekranu przetrwały kolejne
kompilacje ([szczegóły](docs/macos/instalacja.md#podpis-przy-budowaniu)).

## Pull requesty

1. Przy większych zmianach najpierw otwórz zgłoszenie albo dyskusję. Łatwiej ustalić kierunek, zanim powstanie kod.
2. Zrób fork i gałąź od `main`.
3. Trzymaj się stylu otaczającego kodu:
   - teksty w interfejsie **po polsku**, krótko i bez żargonu;
   - komentarze i nazwy w kodzie **po angielsku**;
   - bez zewnętrznych zależności, jeśli nie są naprawdę potrzebne.
4. Sprawdź, że projekt buduje się bez ostrzeżeń.
5. Jeśli zmieniasz wygląd, wygeneruj nowe zrzuty: `cd macos && scripts/snapshots.sh`.
6. Jeśli zmieniasz działanie, zaktualizuj dokumentację w `docs/`.
7. Otwórz PR i wypełnij szablon. CI zbuduje aplikację automatycznie.

Wiadomości commitów piszemy po angielsku, w trybie rozkazującym, np. „Fix marker count after trimming”.

## Licencja

Projekt jest na licencji [PolyForm Noncommercial 1.0.0](LICENSE). Wysyłając zmiany, zgadzasz się, że będą
udostępnione na tej samej licencji.

## Zasady

Obowiązuje nas [kodeks postępowania](.github/CODE_OF_CONDUCT.md). Krótko: życzliwość i szacunek.
