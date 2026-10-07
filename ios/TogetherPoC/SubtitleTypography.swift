import SwiftUI

@MainActor enum SubtitleTypography {
 static func font(_ subtitles:ExternalSubtitles)->Font {
  let design:Font.Design
  switch subtitles.fontFamily {case .system:design = .default;case .rounded:design = .rounded;case .serif:design = .serif}
  let weight:Font.Weight
  switch subtitles.fontWeight {case .light:weight = .light;case .regular:weight = .regular;case .semibold:weight = .semibold;case .bold:weight = .bold}
  return Font.system(size:CGFloat(SubtitleAppearance.font(subtitles.fontSize)),weight:weight,design:design)
 }
}
