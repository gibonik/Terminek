import SwiftUI
import UIKit

// MARK: - Design tokens
//
// Jedyne miejsce w aplikacji, w którym są liczby i kolory. Widoki używają wyłącznie tych nazw.
//
// Zasady:
// 1. Odstępy na siatce 4/8 pt.
// 2. Typografia: systemowy San Francisco w rolach Dynamic Type (Large Title, Body, Caption…).
// 3. Kolory semantyczne, każdy ma wersję jasną i ciemną.
// 4. Promienie: 12 pt karty, 20 pt panele i banery, kapsuła dla pigułek i tagów.
//
// Kierunek: „Midnight”. Prawie czarne tło jak w aplikacjach bankowych i streamingowych,
// jeden elektryczny akcent (fiolet) i nasycone gradientowe karty dokumentów.

typealias DT = DesignTokens

enum DesignTokens {

    // MARK: Odstępy (siatka 4/8 pt)

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        /// Margines ekranu.
        static let gutter: CGFloat = 20
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        /// Miejsce pod pływającym paskiem zakładek.
        static let tabBarClearance: CGFloat = 112
    }

    // MARK: Rozmiary

    enum Size {
        /// Minimalny cel dotyku (HIG).
        static let touch: CGFloat = 44
        /// Wiersz listy.
        static let row: CGFloat = 64
        /// Przełącznik w panelu.
        static let toggleRow: CGFloat = 56
        /// Duży przycisk akcji.
        static let button: CGFloat = 56
        /// Okrągła akcja w szczegółach (jak w aplikacjach bankowych).
        static let actionCircle: CGFloat = 56
        /// Karta dokumentu w karuzeli (proporcje karty ID-1).
        static let card = CGSize(width: 296, height: 188)
        /// Mała karta w rzędach.
        static let railCard = CGSize(width: 168, height: 108)
        /// Miniatura karty w wierszu.
        static let miniCard = CGSize(width: 48, height: 32)
        /// Wysokość baneru na starcie.
        static let hero: CGFloat = 320
        /// Nagłówek szczegółów.
        static let detailHeader: CGFloat = 440
        /// Chip na karcie.
        static let chip = CGSize(width: 36, height: 28)
        /// Hologram na karcie.
        static let hologram = CGSize(width: 40, height: 28)
        /// Pigułka filtra / szybkiej daty.
        static let pill: CGFloat = 36
        /// Pole tekstowe i wyszukiwarka.
        static let field: CGFloat = 48
        /// Komórka dnia w kalendarzu.
        static let dayCell: CGFloat = 40
        static let dot: CGFloat = 4
        static let avatar: CGFloat = 40
        /// Zdjęcie na dowodzie i prawie jazdy.
        static let photo = CGSize(width: 56, height: 72)
        /// Okrągła naklejka przeglądu.
        static let sticker: CGFloat = 88
        /// Plakietka UE.
        static let euBadge = CGSize(width: 40, height: 48)
        static let iconBadge: CGFloat = 36
        static let ring: CGFloat = 56
        static let ringLine: CGFloat = 6
        static let timelineDot: CGFloat = 12
        /// Zakładka w pasku.
        static let tabItem = CGSize(width: 64, height: 48)
        static let lockBadge: CGFloat = 96
        static let lockHalo: CGFloat = 128
        static let scanPreview: CGFloat = 184
        static let tile: CGFloat = 96
        static let hairline: CGFloat = 1
    }

    // MARK: Promienie

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        /// Karty dokumentów, przyciski, kafelki.
        static let card: CGFloat = 12
        /// Panele, banery, arkusze.
        static let panel: CGFloat = 20
        // Pigułki i tagi: `Capsule()`.
    }

    // MARK: Typografia (San Francisco, role Dynamic Type)

    enum Typography {
        static let largeTitle = SwiftUI.Font.largeTitle.weight(.bold)
        static let title = SwiftUI.Font.title.weight(.bold)
        static let title2 = SwiftUI.Font.title2.weight(.bold)
        static let title3 = SwiftUI.Font.title3.weight(.semibold)
        static let headline = SwiftUI.Font.headline
        static let body = SwiftUI.Font.body
        static let callout = SwiftUI.Font.callout
        static let subheadline = SwiftUI.Font.subheadline
        static let subheadlineEmphasized = SwiftUI.Font.subheadline.weight(.semibold)
        static let footnote = SwiftUI.Font.footnote
        static let footnoteEmphasized = SwiftUI.Font.footnote.weight(.semibold)
        static let caption = SwiftUI.Font.caption
        static let captionEmphasized = SwiftUI.Font.caption.weight(.semibold)
        /// Etykiety nad sekcjami: małe wersaliki.
        static let overline = SwiftUI.Font.caption.weight(.bold)
        static let icon = SwiftUI.Font.body.weight(.semibold)
        /// Wielka liczba dni w banerze, skalowana z Dynamic Type.
        static var display: SwiftUI.Font {
            SwiftUI.Font(UIFontMetrics(forTextStyle: .largeTitle)
                .scaledFont(for: .systemFont(ofSize: 88, weight: .heavy)))
        }
        /// Liczba dni na karcie.
        static var cardNumber: SwiftUI.Font {
            SwiftUI.Font(UIFontMetrics(forTextStyle: .title1)
                .scaledFont(for: .systemFont(ofSize: 40, weight: .heavy)))
        }
    }

    // MARK: Kolory (semantyczne, jasny i ciemny)

    enum Palette {
        static let background = adaptive(0xF3F3F7, 0x07070B)
        /// Lekko uniesione tło (górna poświata, arkusze).
        static let backgroundElevated = adaptive(0xFFFFFF, 0x111118)

        static let surface = adaptive(0xFFFFFF, 0xFFFFFF, light: 1, dark: 0.06)
        static let surfaceRaised = adaptive(0xE9E9F0, 0xFFFFFF, light: 1, dark: 0.11)
        static let separator = adaptive(0x0B0B12, 0xFFFFFF, light: 0.08, dark: 0.08)

        static let textPrimary = adaptive(0x0B0B12, 0xF5F5F7)
        static let textSecondary = adaptive(0x646473, 0x9C9CAB)
        static let textTertiary = adaptive(0x9A9AAA, 0x5F5F6E)

        /// Elektryczny fiolet: główne przyciski, zaznaczenia, aktywna zakładka.
        static let accent = adaptive(0x5B3DF5, 0x7C5CFF)
        /// Akcent jako tekst na tle (kontrast 4.5:1 w obu trybach).
        static let accentText = adaptive(0x4B2FE0, 0xAE9BFF)
        static let onAccent = adaptive(0xFFFFFF, 0xFFFFFF)
        /// Drugi kolor gradientu akcentu.
        static let accentAlt = adaptive(0x0891B2, 0x22D3EE)

        static let danger = adaptive(0xD61F45, 0xFF5470)
        static let warning = adaptive(0xA15C00, 0xFFB020)
        static let success = adaptive(0x0E8F68, 0x2EE6A6)
        static let dangerFill = adaptive(0xE11D48, 0xE11D48)
        static let onDanger = adaptive(0xFFFFFF, 0xFFFFFF)

        static let shadow = adaptive(0x1A1A3A, 0x000000, light: 0.14, dark: 0.6)
        static let scrim = adaptive(0x000000, 0x000000)
        static let onScrim = adaptive(0xFFFFFF, 0xFFFFFF)

        // Karty dokumentów to przedmioty: mają swoje gradienty w obu trybach.
        enum Card {
            static let auto = [SwiftUI.Color(hex: 0xFF7A1A), SwiftUI.Color(hex: 0xE11D48)]
            static let home = [SwiftUI.Color(hex: 0x2563EB), SwiftUI.Color(hex: 0x06B6D4)]
            static let personal = [SwiftUI.Color(hex: 0x0D9488), SwiftUI.Color(hex: 0x0E7490)]
            static let subscriptions = [SwiftUI.Color(hex: 0x7C3AED), SwiftUI.Color(hex: 0xDB2777)]
            // Każdy rodzaj dokumentu ma własny wygląd karty.
            static let carInsurance = [SwiftUI.Color(hex: 0xFF7A1A), SwiftUI.Color(hex: 0xE11D48)]
            static let carInspection = [SwiftUI.Color(hex: 0xFBBF24), SwiftUI.Color(hex: 0xEA580C)]
            static let carInspectionInk = SwiftUI.Color(hex: 0x3B1702)
            static let passport = [SwiftUI.Color(hex: 0x881337), SwiftUI.Color(hex: 0x3F0717)]
            static let passportInk = SwiftUI.Color(hex: 0xF5E1A4)
            static let idCard = [SwiftUI.Color(hex: 0xF5D0FE), SwiftUI.Color(hex: 0xBAE6FD)]
            static let idCardInk = SwiftUI.Color(hex: 0x2E1A47)
            static let drivingLicense = [SwiftUI.Color(hex: 0xFBCFE8), SwiftUI.Color(hex: 0xF9A8D4)]
            static let drivingLicenseInk = SwiftUI.Color(hex: 0x4A1033)
            static let homeInsurance = [SwiftUI.Color(hex: 0x2563EB), SwiftUI.Color(hex: 0x06B6D4)]
            static let subscription = [SwiftUI.Color(hex: 0x14102A), SwiftUI.Color(hex: 0x3B0764)]
            static let subscriptionGlow = [SwiftUI.Color(hex: 0x7C3AED), SwiftUI.Color(hex: 0xDB2777)]
            static let other = [SwiftUI.Color(hex: 0x475569), SwiftUI.Color(hex: 0x1E293B)]
            /// Mocniejsze wersje jasnych kart do animowanych banerów (biały tekst).
            static let idCardHero = [SwiftUI.Color(hex: 0xC026D3), SwiftUI.Color(hex: 0x0EA5E9)]
            static let drivingLicenseHero = [SwiftUI.Color(hex: 0xDB2777), SwiftUI.Color(hex: 0x9D174D)]
            static let carInspectionHero = [SwiftUI.Color(hex: 0xF59E0B), SwiftUI.Color(hex: 0xC2410C)]
            /// Niebieska plakietka UE na prawie jazdy.
            static let euBlue = SwiftUI.Color(hex: 0x1D4ED8)
            static let euStar = SwiftUI.Color(hex: 0xFACC15)
            /// Tekst na kartach.
            static let ink = SwiftUI.Color.white
            static let highlight = SwiftUI.Color.white
            static let lowlight = SwiftUI.Color.black
            /// Złoty chip.
            static let chip = [SwiftUI.Color(hex: 0xF5E1A4), SwiftUI.Color(hex: 0xC9A24A)]
            /// Pieczątka „Nieważny”.
            static let stamp = SwiftUI.Color(hex: 0xFFFFFF)
            static let holo: [SwiftUI.Color] = ([0xFF9AD5, 0x9AE6FF, 0xC4FF9A, 0xFFF19A, 0xFFB59A, 0xFF9AD5] as [UInt32])
                .map { SwiftUI.Color(hex: $0) }
        }

        static func adaptive(_ light: UInt32, _ dark: UInt32, light lightAlpha: CGFloat = 1, dark darkAlpha: CGFloat = 1) -> SwiftUI.Color {
            SwiftUI.Color(uiColor: UIColor { trait in
                let isDark = trait.userInterfaceStyle == .dark
                let hex = isDark ? dark : light
                return UIColor(
                    red: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: isDark ? darkAlpha : lightAlpha
                )
            })
        }
    }

    // MARK: Ruch

    enum Motion {
        static let press = Animation.spring(duration: 0.25, bounce: 0.3)
        static let standard = Animation.spring(duration: 0.4, bounce: 0.15)
        static let bouncy = Animation.spring(duration: 0.5, bounce: 0.3)
        static let hero = Animation.spring(duration: 0.6, bounce: 0.2)
    }
}
