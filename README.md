# Terminy

Aplikacja na iPhone'a: wszystkie domowe dokumenty z terminem ważności w jednym miejscu
(OC, przegląd, paszport, dowód, prawo jazdy, subskrypcje), z przypomnieniami
30 i 7 dni przed terminem. Dane w prywatnym iCloud, aplikacja zablokowana Face ID.

## Plan MVP

### Ekrany
1. **Blokada** – zasłania wszystko po wyjściu z aplikacji, odblokowanie Face ID (zapasowo kod telefonu).
2. **Lista dokumentów** – sekcje „Po terminie”, „Wkrótce (do 30 dni)”, „Ważne”, posortowane po dacie.
   Kolorowa plakietka z liczbą dni, filtr po rodzaju, wyszukiwarka (nazwa, osoba, numer).
   Przesunięcie w prawo = „Odnów”, w lewo = usuń. Przycisk + z szablonami rodzajów.
3. **Szczegóły** – data, ile dni zostało, numer, notatki, skan. „Odnowione – przesuń termin”
   (OC/przegląd +1 rok, paszport/dowód +10 lat, subskrypcja o cykl rozliczeniowy).
4. **Dodawanie/edycja** – rodzaj, nazwa, czyje (z podpowiedziami domowników), numer, data,
   przełącznik przypomnień, cena i cykl dla subskrypcji, notatki.
   **Skanuj dokument** albo **Wybierz zdjęcie** → OCR na telefonie podpowiada datę ważności.
5. **Ustawienia** – Face ID wł./wył., godzina przypomnień, skrót do ustawień powiadomień.

### Model danych (SwiftData + CloudKit)
`Document`: `id`, `title`, `categoryRaw` (OC, przegląd, paszport, dowód, prawo jazdy, subskrypcja, inne),
`expiryDate`, `owner`, `number`, `notes`, `remindersEnabled`, `createdAt`,
`price?`, `billingCycleRaw?` (subskrypcje), `scanImageData?` (zewnętrzny zapis).
Wszystkie pola mają wartości domyślne i nie ma ograniczeń `unique` – to wymóg synchronizacji z CloudKit.

### Przypomnienia
Lokalne powiadomienia o wybranej godzinie (domyślnie 9:00): 30 dni przed, 7 dni przed i w dniu terminu.
iOS pozwala na 64 zaplanowane powiadomienia, więc po każdej zmianie (także tej z iCloud z innego
urządzenia) aplikacja przelicza całość i zostawia 60 najbliższych.

### Poza MVP (pomysły na dalej)
Widget z najbliższym terminem, współdzielenie z domownikami (CloudKit sharing), dodawanie do Kalendarza,
odczyt strefy MRZ z paszportu, eksport PDF, dodatkowe przypomnienia per dokument.

## Struktura

```
Terminy/
  App/        TerminyApp (kontener SwiftData + CloudKit), RootView (blokada, przeliczanie przypomnień)
  Models/     Document, DocumentCategory, BillingCycle
  Services/   NotificationScheduler, AppLock (Face ID), DocumentScanner (VisionKit),
              TextRecognizer (Vision OCR), DateExtractor (wyszukiwanie daty ważności w tekście)
  Views/      DocumentListView, DocumentDetailView, DocumentEditView, SettingsView
TerminyTests/ testy odczytu dat i planowania przypomnień
project.yml   definicja projektu dla XcodeGen
```

## Uruchomienie

Wymagany Mac z Xcode 15+ (iOS 17+).

```bash
brew install xcodegen
cd terminy
xcodegen          # tworzy Terminy.xcodeproj
open Terminy.xcodeproj
```

W Xcode:
1. Target **Terminy → Signing & Capabilities**: wybierz swój zespół (wystarczy darmowe Apple ID do
   testów na własnym telefonie, ale **iCloud/CloudKit wymaga płatnego konta deweloperskiego**).
2. Jeśli zmieniasz bundle ID (`pl.terminy.app`), zmień też kontener iCloud w
   `Terminy/Resources/Terminy.entitlements` i `TerminyApp.cloudKitContainerID`.
3. Uruchom na telefonie (⌘R). Testy: ⌘U.

Bez CloudKit (np. darmowe konto albo symulator bez zalogowanego iCloud) aplikacja sama
przełącza się na zapis lokalny, więc da się ją normalnie testować. Skaner dokumentów działa
tylko na prawdziwym urządzeniu; w symulatorze użyj „Wybierz zdjęcie”.

Bez XcodeGen: utwórz w Xcode nowy projekt iOS App (SwiftUI, Storage: None) o nazwie Terminy,
przeciągnij do niego folder `Terminy/`, usuń wygenerowane `ContentView`/`TerminyApp` i dodaj
w Capabilities: iCloud (CloudKit), Push Notifications, Background Modes → Remote notifications,
a w Info klucze `NSFaceIDUsageDescription` i `NSCameraUsageDescription`.
