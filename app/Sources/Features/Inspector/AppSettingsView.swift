import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    var body: some View {
        Form {
            Picker(selection: $preferences.appearance) {
                ForEach(AppAppearance.allCases) { value in Text(value.title).tag(value) }
            } label: {
                Text(L10n.tr("外觀"))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .pickerStyle(.segmented)
            Picker(L10n.tr("介面語言"), selection: $preferences.language) {
                ForEach(AppLanguage.allCases) { value in Text(value.title).tag(value) }
            }
            Text(L10n.tr("語言變更會在下次開啟 App 時生效，不會中斷目前的工作。"))
                .font(.callout).foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if preferences.languageChangePending {
                Text(L10n.tr("語言已儲存，下次開啟生效。"))
                    .foregroundStyle(DS.Palette.asagi)
            }
        }
        .padding(DS.Ma.section)
        .frame(width: 480, height: 250)
        .background(DS.Palette.sumi)
        .preferredColorScheme(preferences.appearance.colorScheme)
        .tint(DS.Palette.asagi)
    }
}
