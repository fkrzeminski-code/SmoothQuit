# SmoothQuit

Natywna aplikacja macOS, która po zamknięciu ostatniego normalnego okna czeka przez wybrany czas, ponownie sprawdza okna i wysyła zwykłe Quit. Animację zamknięcia wykonuje sama aplikacja i macOS.

## Pobieranie

Pobierz `SmoothQuit.dmg` z [GitHub Releases](https://github.com/fkrzeminski-code/SmoothQuit/releases), otwórz obraz i przeciągnij aplikację do **Applications / Aplikacje**. Zakończ wcześniej starą kopię SmoothQuit. Dostępny build jest uniwersalny: Apple Silicon + Intel.

To wersja testowa, podpisana lokalnie **ad hoc**, bez notaryzacji Apple. macOS może zablokować pobrany plik. Jeśli ufasz temu wydaniu, możesz skorzystać ze standardowej opcji systemowej „Otwórz mimo to”, o ile jest dostępna. Nie wyłączaj Gatekeeper ani SIP. Można też zbudować aplikację ze źródeł — bez płatnego konta developerskiego.

## Pierwsze uruchomienie

1. Włącz SmoothQuit w **Ustawienia systemowe → Prywatność i ochrona → Dostępność**. Tylko to uprawnienie jest wymagane. Przycisk „Nadaj dostęp…” prowadzi do właściwej strony.
2. W zakładce **Aplikacje** pozostaw **Include — tylko z listy**. Dodaj jedną aplikację i testuj ją na pustym lub tymczasowym dokumencie. Świeża instalacja ma pustą listę i niczego automatycznie nie zamyka.
3. Włącz **Enable SmoothQuit**. Domyślne opóźnienie wynosi **0,5 s**, dostępny zakres to 0,2–2 s.
4. Opcjonalnie włącz **Uruchamiaj przy logowaniu** po przeniesieniu aplikacji do docelowego folderu Applications.

**Show in Menu Bar** steruje tylko widocznością ikony. Po jej ukryciu otwórz aplikację przez Spotlight lub Finder, aby wrócić do ustawień. Czerwony X zamyka tylko ustawienia. **Enable** wyłącza automatykę i anuluje oczekujące Quit, ale pozostawia program uruchomiony. **Quit SmoothQuit** kończy cały program.

W **Exclude** lista oznacza wyjątki; w **Include** — aplikacje do obsługi. Reguły „Zawsze zezwalaj” i „Nigdy nie zamykaj” mają pierwszeństwo. Finder jest domyślnie chroniony; SmoothQuit zawsze ignoruje własny proces. Istniejące ustawienia są zachowywane podczas aktualizacji.

## Bezpieczeństwo i prywatność

- Nie przechwytuje kliknięć ani klawiszy. Nie ma force quit ani zabijania procesów.
- Nowe okno anuluje odliczanie. Niepewny odczyt AX blokuje Quit.
- Otwarte okna zminimalizowane, ukryte, pomocnicze, pełnoekranowe i zapamiętane na innych Spaces również blokują Quit. Opcje monitorowania tych stanów nie pozwalają ignorować istniejących okien.
- Zwykłe Quit pozwala aplikacji zapytać o zapis dokumentu albo odmówić zakończenia.
- Brak telemetrii, reklam i komunikacji sieciowej. Brak zapisu tytułów okien, treści dokumentów, klawiszy i zrzutów ekranu. Ostatnie 200 wpisów diagnostyki znajduje się tylko w RAM.

Publiczne API nie gwarantują atomowego odczytu wszystkich Spaces i zakończenia obcego procesu. Aplikacje z niepełnym AX mogą pozostać uruchomione. Szczegóły: [model bezpieczeństwa](SAFETY.md), [wyniki i procedura testowania](TESTING.md).

Po przebudowie lub aktualizacji podpis ad hoc może wymagać usunięcia starego wpisu z Dostępności i dodania aktualnego `.app`. Nie uruchamiaj kilku kopii równocześnie. Autostart rejestruj dla kopii zainstalowanej w docelowym miejscu.

## Projekt lokalny

```sh
git clone https://github.com/fkrzeminski-code/SmoothQuit.git
cd SmoothQuit
swift test
./scripts/build.sh
```

Kod, dokumentacja, zasoby i buildy mieszczą się w jednym folderze projektu. Wyniki kompilacji trafiają do `Builds/Preview-1.4.1/` i nie są dodawane do Git. Wymagany pełny Xcode; wydanie sprawdzono z Xcode 27.1. Minimalny cel systemowy to macOS 14, bieżąca kontrola wyglądu obejmuje macOS 27.

## Język

SmoothQuit obsługuje polski i angielski. Aby wybrać angielski tylko dla tej aplikacji, przejdź do Ustawienia systemowe → Ogólne → Język i region → Aplikacje, dodaj SmoothQuit i wybierz English. Uruchom aplikację ponownie.
