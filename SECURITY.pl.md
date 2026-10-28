# Bezpieczeństwo

## Obsługiwane wersje

| Wersja | Poprawki bezpieczeństwa |
|---|---|
| macOS – najnowsze wydanie (`v*`) | ✅ |
| macOS – starsze wydania | ❌ zaktualizuj do najnowszej |
| Windows | w przygotowaniu |

## Jak zgłosić lukę

**Nie zgłaszaj luk w publicznych zgłoszeniach, dyskusjach ani pull requestach.**

Użyj prywatnego formularza GitHuba:
**[Zgłoś lukę](https://github.com/ItsRaelx/ClipRecorder/security/advisories/new)**
(zakładka *Security* → *Report a vulnerability*). Zgłoszenie widzą tylko opiekunowie projektu.

Dopisz:
- wersję aplikacji i systemu;
- opis problemu i jego możliwych skutków;
- kroki do odtworzenia albo proof of concept;
- czy luka jest już gdzieś opisana publicznie.

Potwierdzimy otrzymanie zgłoszenia, ustalimy z Tobą, co dalej, a po wydaniu poprawki opublikujemy opis luki.
Jeśli chcesz, wymienimy Cię w nim jako znalazcę.

## Zakres

W zakresie:
- aplikacje ClipRecorder (macOS, w przyszłości Windows);
- przechowywanie tokenu logowania (pęk kluczy);
- obsługa adresów `cliprecorder://`;
- wysyłanie klipów i komunikacja z serwerem;
- sprawdzanie aktualizacji;
- skrypty budowania i wydawania w tym repozytorium.

Problemy z serwerem [clip.secc.me](https://clip.secc.me) (konta, udostępnione klipy, API) też zgłaszaj tym
formularzem. Przekażemy je dalej.

Poza zakresem:
- uprawnienia macOS, które użytkownik sam nadał aplikacji, np. nagrywanie ekranu;
- ostrzeżenia Gatekeepera przy wydaniach testowych, które nie są podpisane certyfikatem Apple (to znane ograniczenie);
- ataki wymagające wcześniejszego pełnego dostępu do konta użytkownika na komputerze.

## Jak aplikacja chroni dane

- Nagrania nie opuszczają komputera, dopóki nie udostępnisz klipu.
- Token logowania jest w pęku kluczy macOS, nigdy w plikach ustawień. Wylogowanie unieważnia go na serwerze.
- Okna aplikacji są wyłączone z nagrywania. Wybrane aplikacje (np. menedżer haseł) można ukryć w klipach.
- Połączenia z clip.secc.me i z GitHubem idą przez HTTPS. App Transport Security blokuje nieszyfrowane połączenia
  z serwerami w internecie.
