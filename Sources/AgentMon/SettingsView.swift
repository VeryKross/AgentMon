import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var dashboard: DashboardModel
  @AppStorage(SettingsKeys.weatherLocation) private var weatherLocation = SettingsKeys
    .defaultWeatherLocation
  @AppStorage(SettingsKeys.fillSecondaryDisplay) private var fillSecondaryDisplay = true
  @AppStorage(SettingsKeys.computerName) private var computerName = "Ken's M4 Mini"
  @AppStorage(SettingsKeys.relayEnabled) private var relayEnabled = false
  @AppStorage(SettingsKeys.relayURL) private var relayURL =
    "https://windows-desktop.local:\(RelayProtocol.defaultPort)"
  @AppStorage(SettingsKeys.relayFingerprint) private var relayFingerprint = ""
  @State private var relayToken: String
  @State private var relaySaveError: String?

  init() {
    _relayToken = State(initialValue: (try? RelayKeychain.loadToken()) ?? "")
  }

  var body: some View {
    Form {
      Section("Display") {
        TextField("Computer name", text: $computerName)
          .textFieldStyle(.roundedBorder)
        Toggle("Fill the secondary display when AgentMon opens", isOn: $fillSecondaryDisplay)
        Text("If only one display is connected, AgentMon opens as a normal window.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Weather") {
        TextField("Town, city, or ZIP code", text: $weatherLocation)
          .textFieldStyle(.roundedBorder)

        HStack {
          Text(
            "Open-Meteo forecast data; U.S. conditions observed by the National Weather Service."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Spacer()
          Button("Refresh Weather") {
            dashboard.refresh(forceWeather: true)
          }
          .disabled(weatherLocation.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }

      Section("Windows Relay") {
        Toggle("Include sessions from a Windows relay", isOn: $relayEnabled)

        TextField("Relay URL", text: $relayURL)
          .textFieldStyle(.roundedBorder)
        TextField("Certificate SHA-256 fingerprint", text: $relayFingerprint)
          .textFieldStyle(.roundedBorder)
          .font(.system(.caption, design: .monospaced))
        SecureField("Pairing token", text: $relayToken)
          .textFieldStyle(.roundedBorder)

        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(relaySaveError ?? dashboard.relayState.description)
              .font(.caption)
              .foregroundStyle(relaySaveError == nil ? Color.secondary : Color.red)
            Text("The token is stored in this Mac's Keychain.")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("Save & Test") {
            saveRelay()
          }
        }
      }

      Section("Privacy") {
        Text(
          "System and local Copilot status are read on this Mac. A paired relay sends only normalized project and activity metadata over pinned HTTPS—never prompts, source code, or raw events. AgentMon sends only the configured location to weather and geocoding providers."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding(12)
    .frame(width: 520, height: 610)
    .onSubmit {
      dashboard.refresh(forceWeather: true)
    }
  }

  private func saveRelay() {
    do {
      guard let url = URL(string: relayURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        throw RelayClientError.invalidConfiguration("Enter a valid relay URL.")
      }
      let token = relayToken.trimmingCharacters(in: .whitespacesAndNewlines)
      let configuration = RelayConfiguration(
        baseURL: url,
        certificateFingerprint: relayFingerprint,
        token: token
      )
      try configuration.validate()
      try RelayKeychain.saveToken(token)
      relayEnabled = true
      relaySaveError = nil
      dashboard.refreshRelay(force: true)
    } catch {
      relaySaveError = error.localizedDescription
    }
  }
}
