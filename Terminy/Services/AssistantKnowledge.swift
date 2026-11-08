import Foundation

// Wiedza asystenta o samej aplikacji, rozmowa i odmowy.
// Wszystko jest regułami po polsku, działa bez internetu.

extension Assistant {

    // MARK: Odmowy

    /// Tematy, w których asystent nie pomaga: grzecznie odmawia i mówi, w czym pomoże.
    func refusal(_ q: String, mentionsDocument: Bool) -> Reply? {
        // Podrabianie i obchodzenie zabezpieczeń: zawsze odmowa, nawet gdy pada nazwa dokumentu.
        if Self.has(q, ["podrob", "sfalsz", "falszyw", "falszow", "lewy dowod", "lewe prawo", "kupic dowod", "kupic prawo jazdy",
                        "kupic paszport", "obejsc blokad", "zlamac", "zhakow", "hakow", "cudzy dowod", "cudze dane", "ukrasc"]) {
            return Reply(text: "W tym nie pomogę. Podrabianie dokumentów i korzystanie z cudzych danych to przestępstwo. Mogę za to podpowiedzieć, jak legalnie wyrobić albo odnowić dokument.",
                         actions: [.ask("Jak odnowić dowód?"), .ask("Jak odnowić paszport?")])
        }

        // Kary za brak ważnego dokumentu: ogólna informacja, bez porady prawnej.
        if Self.has(q, ["kara", "kary", "mandat", "grzywn", "co grozi", "co mi grozi", "ufg"]) {
            if Self.has(q, [" oc", "ubezpiecz", "polis"]) {
                return Reply(text: "Za brak ważnego OC Ubezpieczeniowy Fundusz Gwarancyjny nalicza karę, zależną od długości przerwy i płacy minimalnej. Przy dłuższej przerwie to kilka tysięcy złotych. Aktualne stawki sprawdzisz na ufg.pl. To ogólna informacja, nie porada prawna.",
                             actions: [.ask("Kiedy kończy się OC?")])
            }
            if Self.has(q, ["przeglad", "badani"]) {
                return Reply(text: "Za jazdę bez ważnego badania technicznego grozi mandat, a policja może zatrzymać dowód rejestracyjny. Szczegóły i aktualne stawki znajdziesz na gov.pl. To ogólna informacja, nie porada prawna.",
                             actions: [.ask("Kiedy jest przegląd?")])
            }
            return Reply(text: "Nie udzielam porad prawnych i nie znam aktualnych taryfikatorów. Sprawdź gov.pl albo zapytaj prawnika. Mogę za to pilnować, żeby żaden termin Ci nie uciekł.",
                         actions: [.ask("Co jest po terminie?")])
        }

        // Porady prawne, medyczne i finansowe.
        if Self.has(q, ["porad prawn", "prawnik", "adwokat", "pozwac", "pozew", "sad ", "sadzie", "lekarz", "choroba", "chory",
                        "objaw", "leki", "inwest", "kredyt", "pozyczk", "podatek", "podatk", "pit ", "kryptowalut", "gield"]) && !mentionsDocument {
            return Reply(text: "Na takie pytania nie odpowiem, bo nie jestem doradcą prawnym, medycznym ani finansowym. Zajmuję się Twoimi dokumentami i terminami. W tym chętnie pomogę.",
                         actions: [.ask("Co mam najbliżej?"), .ask("Co umiesz?")])
        }

        // Prośby o wysłanie danych gdzieś na zewnątrz.
        if Self.has(q, ["wyslij", "przeslij", "udostepnij", "wrzuc"]) && Self.has(q, ["mail", "sms", "facebook", "messenger", "whatsapp", "internet", "chmur", "komus", "do kogos"]) {
            return Reply(text: "Sam niczego nie wysyłam, nawet nie mam dostępu do internetu. Dokument udostępnisz Ty: otwórz kartę i stuknij strzałkę w prawym górnym rogu. Skan wyślesz jako PDF z podglądu skanu.",
                         actions: [.ask("Jak zrobić kopię zapasową?")])
        }

        guard !mentionsDocument else { return nil }

        // Tematy spoza aplikacji.
        let offTopic = ["pogod", "przepis na", "ugotowac", "dowcip", "zart", "kawal", "mecz", "pilka", "polityk", "wybor", "prezydent", "premier",
                        "przetlumacz", "tlumacz", "napisz wiersz", "napisz wypracowanie", "napisz kod", "programow", "ile to jest", "policz mi",
                        "stolica", "kto wygral", "film", "serial do obejrzenia", "piosenk", "horoskop", "lotto", "bitcoin", "kurs euro", "kurs dolara",
                        "randk", "milosc", "nudzi mi sie", "opowiedz bajke", "historia polski"]
        if Self.has(q, offTopic) {
            return Reply(text: "Z tym nie pomogę, bo znam się tylko na Twoich dokumentach i na Terminku. Działam bez internetu, więc nie sprawdzę pogody, wiadomości ani niczego w sieci. Zapytaj o terminy, a odpowiem od razu.",
                         actions: [.ask("Co mam najbliżej?"), .ask("Podsumuj moje dokumenty"), .ask("Co umiesz?")])
        }

        // Obraźliwe wiadomości: spokojnie i dalej do rzeczy.
        if Self.has(q, ["glupi", "debil", "idiot", "kurw", "spierdal", "chuj", "beznadziejn", "do dupy"]) {
            return Reply(text: "Przykro mi, że coś nie działa tak, jak trzeba. Napisz, co dokładnie się stało, albo zgłoś problem, a twórca to poprawi.",
                         actions: [.report, .ask("Co umiesz?")])
        }
        return nil
    }

    // MARK: Rozmowa

    func smallTalk(_ q: String, documents: [Document]) -> Reply? {
        let words = q.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let short = words.count <= 4

        let greetings: Set<String> = ["czesc", "hej", "siema", "witaj", "witam", "elo", "hejka", "yo", "halo", "hello", "hi", "siemka", "czolem"]
        let isGreeting = words.first.map(greetings.contains) ?? false || q.hasPrefix("dzien dobry") || q.hasPrefix("dobry wieczor")
        if short, isGreeting {
            let soon = documents.filter { (0...7).contains($0.daysLeft(from: now, calendar: calendar)) }
            let expired = documents.filter { $0.daysLeft(from: now, calendar: calendar) < 0 }
            var text = "Cześć! "
            if documents.isEmpty {
                text += "Nie masz jeszcze dokumentów. Zacznij od skanu, a ja przypilnuję terminu."
                return Reply(text: text, actions: [.scan, .ask("Jakie dokumenty mogę dodać?")])
            }
            if !expired.isEmpty { text += "Masz \(Self.documentsCount(expired.count)) po terminie. " }
            if !soon.isEmpty { text += "W tym tygodniu kończy się: \(Self.list(soon.map(\.displayTitle))). " }
            if expired.isEmpty && soon.isEmpty { text += "W tym tygodniu nic się nie kończy. " }
            text += "O co chcesz zapytać?"
            return Reply(text: text, actions: [.ask("Co mam najbliżej?"), .ask("Podsumuj moje dokumenty")])
        }

        let thanks: Set<String> = ["dzieki", "dziekuje", "dziekowac", "thx", "super", "spoko", "okej", "ok", "git", "fajnie", "swietnie", "dobrze", "jasne", "rozumiem"]
        if short, words.contains(where: thanks.contains), intentFree(q) {
            return Reply(text: "Proszę bardzo! Przypomnę, zanim coś się skończy.")
        }

        if Self.has(q, ["kim jestes", "czym jestes", "jestes ai", "jestes botem", "jestes czlowiekiem", "sztuczn", "chatgpt", "chat gpt",
                        "jak dzialasz", "skad wiesz", "czy jestes", "jak masz na imie", "jak sie nazywasz"]) {
            return Reply(text: "Jestem asystentem Terminka. Nie jestem czatem z internetu, tylko zestawem reguł działającym na Twoim telefonie. Widzę Twoje dokumenty w aplikacji i jej ustawienia, liczę terminy i znam wszystkie funkcje Terminka. Nic nie wysyłam i nie mam dostępu do sieci, więc nie wiem nic spoza aplikacji.",
                         actions: [.ask("Co umiesz?")])
        }
        return nil
    }

    /// Krótka wiadomość bez pytania o coś konkretnego (np. „ok dzięki”, ale nie „ok, kiedy OC?”).
    private func intentFree(_ q: String) -> Bool {
        !Self.has(q, ["kiedy", "ile", "jak", "co ", "czy", "gdzie", "?"])
    }

    // MARK: Wiedza o aplikacji

    /// Odpowiedzi na pytania o funkcje Terminka. `nil`, gdy pytanie dotyczy dokumentów.
    func knowledge(_ q: String, intent: Intent, mentionsDocument: Bool, documents: [Document]) -> Reply? {
        let count = documents.count

        // Skan nie działa: przed ogólnym „jak skanować”.
        if Self.has(q, ["nie odczyt", "nie czyta", "nie rozpozna", "zle odczyt", "zla data", "zly termin", "nie wykrywa", "skan nie",
                        "nie dziala skan", "nie skanuje", "nie wczytal", "zle sie wpisal", "data wydania", "zamiast daty"]) {
            return Reply(text: """
            Kilka rzeczy, które pomagają przy skanie:
            • Połóż dokument płasko na ciemnym tle, przy dobrym świetle, bez odblasków.
            • Dowód i paszport: zeskanuj stronę ze strefą MRZ (wiersze z „<<<”). Odczytuję z niej numer i datę ważności, a data wydania nie myli się wtedy z datą ważności.
            • Jeśli data się nie wpisała, stuknij „Pokaż odczytany tekst” pod skanem. Zobaczysz, co telefon przeczytał.
            • Zawsze możesz ustawić datę ręcznie, a skan i tak się zapisze.
            Dalej nie działa? Zgłoś problem, najlepiej z odczytanym tekstem (bez PESEL-u).
            """, actions: [.scan, .report])
        }

        if Self.has(q, ["jak zeskan", "jak skan", "skanowan", "zeskanowac", "skaner", "zdjecie dokumentu", "z galerii", "zrobic zdjecie", "skanuje", "zeskanuj"]) && !mentionsDocument {
            return Reply(text: """
            Skanowanie:
            1. Stuknij plus na dole i „Zeskanuj dokument” (albo wybierz zdjęcie z galerii).
            2. Ustaw dokument w ramce. Aparat zrobi zdjęcie sam.
            3. Odczytam rodzaj, datę ważności, numer i nazwisko, a pola ze skanu podświetlę.
            4. Sprawdź datę i zapisz.
            Rozpoznawanie tekstu działa na telefonie, zdjęcia nigdzie nie wychodzą. \(state.isPlus ? "Masz Plus, więc skan może mieć wiele stron." : "W darmowym planie skan ma jedną stronę, w Plus dowolnie wiele.")
            """, actions: [.scan])
        }

        if Self.has(q, ["jak dodac", "dodaj dokument", "nowy dokument", "dodac dokument", "jak wpisac", "jak zapisac dokument", "chce dodac"]) && !mentionsDocument {
            var text = "Stuknij fioletowy plus na dole i wybierz rodzaj dokumentu albo od razu skan. Wystarczy nazwa i data ważności, reszta jest opcjonalna."
            if !state.isPlus { text += " W darmowym planie możesz mieć \(Store.freeDocuments) dokumentów (teraz masz \(count))." }
            return Reply(text: text, actions: [.add(nil), .scan])
        }

        if Self.has(q, ["jakie dokumenty", "co moge dodac", "jakie rodzaje", "co mozna dodac", "jakie kategorie", "czy moge dodac"]) {
            return Reply(text: "Mam gotowe karty dla: OC, przeglądu auta, prawa jazdy, dowodu, paszportu, ubezpieczenia mieszkania i subskrypcji. Wszystko inne z datą (gwarancja, legitymacja, EKUZ, karta parkingowa, leasing) dodasz jako „Inne”.",
                         actions: [.add(nil), .ask("Czego mi brakuje?")])
        }

        if Self.has(q, ["jak edyt", "zmienic date", "zmienic termin", "jak usun", "usunac dokument", "skasowac dokument", "poprawic date", "edytowac", "zmienic nazwe"]) && !mentionsDocument {
            return Reply(text: "Otwórz kartę dokumentu. „Edytuj” zmienia dane i datę, „Odnów” przesuwa termin o typowy okres, a „Usuń” kasuje dokument razem z przypomnieniami. Na liście możesz też przytrzymać kartę, żeby szybko odnowić albo edytować.")
        }

        if Self.has(q, ["co robi odnow", "przycisk odnow", "jak dziala odnow", "co znaczy odnow", "odnow robi"]) {
            return Reply(text: "„Odnów” przesuwa termin o typowy okres: OC, przegląd i polisę mieszkania o rok, dowód i paszport o 10 lat, prawo jazdy o 15 lat, subskrypcję o jej cykl płatności. Liczę od starej daty, a jeśli minęła, od dziś. Przez kilka sekund możesz to cofnąć.")
        }

        // Kłopoty z powiadomieniami: przed ogólnym pytaniem o przypomnienia.
        if Self.has(q, ["nie dostaje", "nie przychodz", "nie ma powiadomien", "brak powiadomien", "nie dziala powiadom", "nie dzialaja powiadom",
                        "nie przyszlo", "nie przypomnial", "nie dostalem", "nie dostalam"]) {
            var text = "Sprawdź po kolei:\n• Ustawienia iPhone'a › Powiadomienia › Terminek: włączone.\n• Tryb skupienia (np. Nie przeszkadzać) może je wyciszać.\n• W Koncie stuknij „Wyślij próbne powiadomienie”. Przyjdzie za 5 sekund.\n• Przypomnienia przychodzą o \(state.reminderHour):00."
            if state.notificationsAllowed == false { text = "Powiadomienia dla Terminka są wyłączone w Ustawieniach iPhone'a, dlatego nic nie przychodzi. Włącz je w Konto › baner na górze albo w Ustawieniach.\n\n" + text }
            return Reply(text: text, actions: [.settings, .report])
        }

        if intent == .reminders && !mentionsDocument {
            return Self.remindersGeneral(state)
        }

        if Self.has(q, ["face id", "faceid", "blokad", "touch id", "kod do aplikacji", "zabezpieczyc aplikacje", "zablokowac aplikacje", "haslo do aplikacji"]) {
            return Reply(text: "Blokada \(state.biometry) jest teraz \(state.lockEnabled ? "włączona" : "wyłączona"). Gdy jest włączona, aplikacja zamyka się za każdym razem, gdy z niej wychodzisz, a w przełączniku aplikacji widać tylko logo. Zmienisz to w Konto › Bezpieczeństwo.",
                         actions: [.settings])
        }

        if Self.has(q, ["prywatn", "bezpieczn", "moje dane", "dane osobowe", "czy wysyla", "wysylasz", "serwer", "kto widzi", "szyfr", "rodo",
                        "gdzie sa moje", "gdzie trzyma", "czy ktos widzi", "sledzi", "reklam"]) {
            return Reply(text: """
            Twoje dane zostają u Ciebie:
            • Dokumenty i skany są tylko w aplikacji na tym telefonie\(state.usesCloud ? " i w Twoim prywatnym iCloud" : ""). Nie ma konta ani serwera Terminka.
            • Skany są zaszyfrowane, gdy telefon jest zablokowany, a odczyt tekstu działa bez internetu.
            • Siri i widżet dostają tylko nazwę i datę, bez numerów i skanów.
            • Nie ma reklam ani śledzenia. Raporty awarii wysyłasz sam, jeśli chcesz.
            Szczegóły są w polityce prywatności (Konto › Informacje).
            """, actions: [.settings])
        }

        if Self.has(q, ["pesel"]) {
            return Reply(text: "PESEL-u celowo nie zapisuję i nie odczytuję ze skanów. Nie jest potrzebny do pilnowania terminów, a to najbardziej wrażliwa dana. Nie wpisuj go też w notatki.")
        }

        if Self.has(q, ["kopia", "kopii", "kopie", "backup", "nowy telefon", "zmiana telefonu", "zmienie telefon", "przeniesc", "przenies", "eksport",
                        "import", "stracic dane", "strace dane", "zgubie", "reinstal", "usune aplikacje", "odinstaluj"]) {
            var text = "Kopię zrobisz w Konto › Kopia zapasowa › Zapisz kopię. To jeden plik ze wszystkimi dokumentami i skanami, zaszyfrowany Twoim hasłem. Zapisz go w Plikach, na dysku albo wyślij sobie mailem. Na nowym telefonie wybierz „Wczytaj kopię” i podaj hasło."
            if let last = state.lastBackup {
                text += " Ostatnia kopia: \(PL.date(last))."
            } else if !state.usesCloud {
                text += " Nie masz jeszcze żadnej kopii, a bez iCloud dane są tylko na tym telefonie. Warto zrobić ją teraz."
            }
            text += " Hasła nie da się odzyskać, więc je zapamiętaj."
            return Reply(text: text, actions: [.backup])
        }

        if Self.has(q, ["icloud", "synchroniz", "drugi telefon", "ipad", "innym urzadzeniu", "na dwoch", "chmur"]) {
            let text = state.usesCloud
                ? "Dokumenty synchronizują się przez Twój prywatny iCloud, więc zobaczysz je na każdym iPhonie z tym samym Apple ID."
                : "Teraz dokumenty są tylko na tym telefonie. Synchronizacja przez iCloud zadziała w wersji z App Store. Do tego czasu przenieś dane kopią zapasową."
            return Reply(text: text, actions: state.usesCloud ? [] : [.backup])
        }

        // Terminek Plus: pytania o aplikację, nie o subskrypcje użytkownika.
        let aboutPlus = Self.has(q, ["plus", "premium", "wersja platna", "wersji platnej", "pelna wersj", "odblokuj", "terminek pro", "pro wersj"])
        if aboutPlus && Self.has(q, ["anul", "zrezygn", "wylacz", "zwrot", "przywroc", "odzyska"]) {
            return Reply(text: "Plus kupujesz przez Apple. Anulujesz go w Ustawienia › Twoje imię › Subskrypcje (najpóźniej 24 godziny przed odnowieniem). Zwroty rozpatruje Apple na reportaproblem.apple.com. Po zmianie telefonu stuknij „Przywróć zakupy” w Koncie.",
                         actions: [.settings])
        }
        if aboutPlus || Self.has(q, ["limit", "darmow", "za darmo", "ile moge dodac", "ile dokumentow moge", "czy aplikacja jest platna", "ile kosztuje aplikacja", "ile kosztuje terminek"]) {
            var text = state.isPlus ? "Masz Terminek Plus, więc wszystko jest odblokowane." : "Masz darmowy plan: \(Store.freeDocuments) dokumentów (masz \(count)), skan jednej strony i \(Store.freeAssistantPerDay) pytania do mnie dziennie\(state.questionsLeft.map { " (dziś zostało: \($0))" } ?? "")."
            text += "\n\nPlus daje: dokumenty bez limitu, skany wielostronicowe w PDF, pytania bez limitu, własne dni przypomnień dla każdego dokumentu i dodawanie terminów do Kalendarza. Kosztuje 9,99 zł miesięcznie, 69,99 zł rocznie (7 dni za darmo) albo 199,99 zł raz na zawsze."
            return Reply(text: text, actions: state.isPlus ? [] : [.plus])
        }

        if Self.has(q, ["siri", "skrot", "przycisk czynnos", "action button", "centrum sterowania", "spotlight", "stukniecie w tyl"]) {
            return Reply(text: "Siri nie mówi po polsku, ale skróty Terminka działają: po angielsku przez Siri („What's my next deadline in Terminek”), a po polsku w aplikacji Skróty, w Spotlight, pod przyciskiem czynności i w Centrum sterowania. Pełna lista fraz jest w Konto › Siri i skróty.",
                         actions: [.siriHelp])
        }

        if Self.has(q, ["widzet", "widget", "na ekranie glownym", "na ekran glowny", "ekran blokady"]) {
            return Reply(text: "Przytrzymaj puste miejsce na ekranie głównym, stuknij „Edytuj” › „Dodaj widżet” i wybierz Terminek. Widżet pokazuje najbliższy termin, a średni także kolejne. Na ekranie blokady nazwy są ukryte, dopóki telefon jest zablokowany. Jeśli widżet pisze „Otwórz Terminka”, uruchom raz aplikację.")
        }

        if Self.has(q, ["kalendarz", "google calendar", "do kalendarza"]) && !mentionsDocument {
            return Reply(text: "Wszystkie terminy widzisz w zakładce Kalendarz. Termin wybranego dokumentu dodasz też do Kalendarza iPhone'a z alarmem: karta dokumentu › Przypomnienia › „Dodaj do Kalendarza”\(state.isPlus ? "." : " (w Plus).")")
        }

        if Self.has(q, ["ciemny", "jasny", "motyw", "tryb nocny", "dark mode", "kolory aplikacji", "zmienic wyglad"]) {
            return Reply(text: "Motyw zmienisz w Konto › Wygląd: jak w systemie, jasny albo ciemny.", actions: [.settings])
        }

        if Self.has(q, ["wibrac", "haptyk", "drgani"]) {
            return Reply(text: "Wibracje wyłączysz w Konto › Bezpieczeństwo i urządzenie › Wibracje.", actions: [.settings])
        }

        if Self.has(q, ["rodzin", "wspoln", "zona", "maz", "meza", "partner", "dzieci", "dziecka", "dla kogos", "innej osoby"]) && !mentionsDocument {
            return Reply(text: "Dokumenty bliskich dodasz już teraz: wpisz imię w polu „Czyj”, a potem pytaj np. „kiedy paszport Ani?”. Wspólny sejf rodzinny, w którym kilka osób widzi te same dokumenty, jest w planach.",
                         actions: [.add(nil)])
        }

        if Self.has(q, ["usun konto", "usun wszystko", "wyczysc dane", "skasuj wszystko", "usunac wszystkie", "usunac konto"]) {
            return Reply(text: "Terminek nie ma konta, więc nie ma czego zamykać. Dokumenty usuniesz pojedynczo z karty, a usunięcie aplikacji kasuje wszystkie dane z telefonu. Zanim to zrobisz, zapisz kopię zapasową.",
                         actions: [.backup])
        }

        if Self.has(q, ["regulamin", "polityka prywatnosci", "polityke prywatnosci", "warunki korzystania"]) {
            return Reply(text: "Regulamin i politykę prywatności znajdziesz w Konto › Informacje. Są też linki na ekranie Terminek Plus.", actions: [.settings])
        }

        if Self.has(q, ["blad", "bug", "zglos", "zawiesza", "wywala", "zamyka sie", "crash", "nie dziala", "psuje", "zepsul", "problem z aplikacj"]) {
            return Reply(text: "Przykro mi! Zgłoś to, a twórca aplikacji to poprawi. Opisz, co robiłeś tuż przed problemem. Możesz dołączyć zrzut ekranu i informacje o telefonie (bez Twoich dokumentów). Zgłoszenie otworzysz też potrząsając telefonem.",
                         actions: [.report])
        }

        if Self.has(q, ["pomysl", "sugest", "propozycj", "brakuje mi funkcj", "dodajcie", "mozecie dodac", "fajnie by bylo"]) {
            return Reply(text: "Super, chętnie poznam pomysł! Wyślij go przez „Zgłoś problem” i wybierz „Pomysł”. Trafi prosto do twórcy.", actions: [.report])
        }

        if Self.has(q, ["jak dziala aplikacj", "do czego sluzy", "co robi aplikacj", "co to za aplikacj", "po co ta aplikacj"]) {
            return Reply(text: "Terminek pilnuje dat ważności: OC, przeglądu, dowodu, paszportu, prawa jazdy, polis i abonamentów. Dodajesz dokument (najszybciej skanem), a ja przypominam miesiąc, tydzień i dzień przed terminem. Wszystko zostaje na Twoim telefonie.",
                         actions: [.scan, .ask("Co umiesz?")])
        }

        return nil
    }

    static func remindersGeneral(_ state: AppState) -> Reply {
        let names = state.offsets.sorted(by: >).map { offset -> String in
            switch offset {
            case 0: return "w dniu terminu"
            case 7: return "tydzień przed"
            case 30: return "miesiąc przed"
            default: return "\(offset) dni przed"
            }
        }
        var text = names.isEmpty
            ? "Wszystkie ogólne przypomnienia są wyłączone."
            : "Przypominam \(list(names)), o \(state.reminderHour):00."
        text += " Zmienisz to w Konto › Przypomnienia. Dla pojedynczego dokumentu ustawisz własne dni (np. 60, 14 i 3 dni przed) na jego karcie\(state.isPlus ? "." : ", w Plus.")"
        if state.notificationsAllowed == false {
            text += "\n\nUwaga: powiadomienia są wyłączone w Ustawieniach iPhone'a."
        }
        return Reply(text: text, actions: [.settings])
    }
}
