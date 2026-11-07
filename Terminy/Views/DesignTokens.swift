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
// 4. Promienie: 12 pt dla kart, 16 pt dla paneli, kapsuła dla pigułek i tagów.

typealias DT = DesignTokens

enum DesignTokens {

    // MARK: Odstępy (siatka 4/8 pt)

    enum Space {
        /// 4
        static let xxs: CGFloat = 4
        /// 8
        static let xs: CGFloat = 8
        /// 12
        static let sm: CGFloat = 12
        /// 16
        static let md: CGFloat = 16
        /// 20, margines ekranu
        static let gutter: CGFloat = 20
        /// 24
        static let lg: CGFloat = 24
        /// 32
        static let xl: CGFloat = 32
        /// 48
        static let xxl: CGFloat = 48
        /// Miejsce pod pływającym dockiem.
        static let dockClearance: CGFloat = 120
    }

    // MARK: Rozmiary

    enum Size {
        /// Minimalny cel dotyku (HIG).
        static let touch: CGFloat = 44
        /// Wiersz listy / przełącznik w panelu.
        static let row: CGFloat = 56
        /// Duży przycisk akcji.
        static let button: CGFloat = 56
        /// Wysokość karty dokumentu (proporcje karty ID-1, 85,6 × 54 mm).
        static let cardHeight: CGFloat = 216
        /// Ile karty widać spod następnej w stosie.
        static let cardPeek: CGFloat = 64
        /// Miniatura karty w wierszu.
        static let miniCard = CGSize(width: 48, height: 32)
        /// Hologram na karcie.
        static let hologram = CGSize(width: 56, height: 40)
        /// Kolumna ikon w wierszach ustawień.
        static let iconColumn: CGFloat = 28
        /// Komórka dnia w kalendarzu.
        static let dayCell: CGFloat = 40
        static let dot: CGFloat = 4
        /// Zakładka w docku.
        static let dockItem = CGSize(width: 56, height: 48)
        /// Mosiężny plus w docku.
        static let dockPlus: CGFloat = 56
        /// Ikona w kółku na ekranie blokady.
        static let lockBadge: CGFloat = 96
        static let lockHalo: CGFloat = 128
        /// Podgląd skanu.
        static let scanPreview: CGFloat = 184
        /// Kafelek w siatce kategorii.
        static let tile: CGFloat = 96
        /// Pusty slot karty w pustym portfelu.
        static let emptySlot: CGFloat = 184
        /// Kropka na osi czasu.
        static let timelineDot: CGFloat = 12
        /// Pigułka filtra / szybkiej daty.
        static let chip: CGFloat = 36
        /// Pole wyszukiwania.
        static let field: CGFloat = 48
        static let hairline: CGFloat = 1
    }

    // MARK: Promienie

    enum Radius {
        /// Miniatury, pieczątka.
        static let xs: CGFloat = 4
        /// Małe elementy wewnątrz kart (hologram, skan).
        static let sm: CGFloat = 8
        /// Karty dokumentów, przyciski, kafelki.
        static let card: CGFloat = 12
        /// Panele na tle.
        static let panel: CGFloat = 16
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
        /// Ikony obok tekstu body.
        static let icon = SwiftUI.Font.body.weight(.semibold)
        /// Liczba dni na karcie: największy tekst w aplikacji, skalowany z Dynamic Type.
        static var display: SwiftUI.Font {
            SwiftUI.Font(UIFontMetrics(forTextStyle: .largeTitle)
                .scaledFont(for: .systemFont(ofSize: 56, weight: .heavy)))
        }
    }

    // MARK: Kolory (semantyczne, jasny i ciemny)

    enum Palette {
        // Tło: skóra portfela. Jasna w trybie jasnym, ciemna w ciemnym.
        static let backgroundTop = adaptive(0xF7F1E8, 0x3A2F27)
        static let background = adaptive(0xEFE6DA, 0x231C17)
        static let backgroundDeep = adaptive(0xE4D8C8, 0x16110E)
        /// Ziarno skóry.
        static let grainLight = adaptive(0xFFFFFF, 0xFFFFFF, light: 0.35, dark: 0.035)
        static let grainDark = adaptive(0x5A4632, 0x000000, light: 0.06, dark: 0.12)

        /// Panel na tle.
        static let surface = adaptive(0xFFFFFF, 0xFFFFFF, light: 0.62, dark: 0.07)
        /// Przycisk lub wybrany element na panelu.
        static let surfaceRaised = adaptive(0xFFFFFF, 0xFFFFFF, light: 0.92, dark: 0.12)
        static let separator = adaptive(0x2A211B, 0xFFFFFF, light: 0.1, dark: 0.09)

        static let textPrimary = adaptive(0x2A211B, 0xF6EBDD)
        static let textSecondary = adaptive(0x6B5D52, 0xB6ACA1)
        static let textTertiary = adaptive(0x9A8C80, 0x857B71)

        /// Mosiądz: wypełnienie głównych przycisków i zaznaczeń.
        static let accent = adaptive(0xE2B05A, 0xFFD68C)
        /// Mosiądz jako tekst i ikona na tle (ciemniejszy w jasnym, dla kontrastu 4.5:1).
        static let accentText = adaptive(0x8A5A0B, 0xFFD68C)
        /// Tekst na mosiądzu.
        static let onAccent = adaptive(0x2A1A08, 0x2A1A08)

        /// Po terminie.
        static let danger = adaptive(0xB8202F, 0xFF6B6B)
        /// Do 7 dni.
        static let warning = adaptive(0x9C4F00, 0xFFB25C)
        /// Pełne tło komunikatu o błędzie.
        static let dangerFill = adaptive(0xC62839, 0xD93A4C)
        static let onDanger = adaptive(0xFFFFFF, 0xFFFFFF)

        static let shadow = adaptive(0x3A2A1A, 0x000000, light: 0.18, dark: 0.45)
        static let scrim = adaptive(0x000000, 0x000000)
        static let onScrim = adaptive(0xFFFFFF, 0xFFFFFF)

        // Karty dokumentów to przedmioty: mają swój kolor w obu trybach.
        enum Card {
            static let auto = SwiftUI.Color(hex: 0xF07A3A)
            static let home = SwiftUI.Color(hex: 0x4A90E2)
            static let personal = SwiftUI.Color(hex: 0x2BB08C)
            static let subscriptions = SwiftUI.Color(hex: 0xF2C230)
            static let autoInk = SwiftUI.Color(hex: 0x2B1305)
            static let homeInk = SwiftUI.Color(hex: 0x061D38)
            static let personalInk = SwiftUI.Color(hex: 0x032A1F)
            static let subscriptionsInk = SwiftUI.Color(hex: 0x2E2300)
            /// Odblask, krawędź i wytłoczenie na plastiku.
            static let highlight = SwiftUI.Color.white
            static let lowlight = SwiftUI.Color.black
            /// Pieczątka „Nieważny”.
            static let stamp = SwiftUI.Color(hex: 0xB3122B)
            /// Folia hologramu.
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
        static let open = Animation.spring(duration: 0.55, bounce: 0.18)
        static let close = Animation.spring(duration: 0.5, bounce: 0.15)
    }
}
