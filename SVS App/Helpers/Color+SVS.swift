//
//  Color+SVS.swift
//  SVS App
//
//  Created by Hussein Souleiman on 22.01.26.
//

import SwiftUI

// MARK: - Compatibility helpers used across the app
extension Color {

    static func svsAccentColor(from colorName: String?) -> Color {
        UserColor.from(colorName).color
    }

    static func svsGermanColorName(from colorName: String?) -> String {
        UserColor.from(colorName).germanName
    }
}
