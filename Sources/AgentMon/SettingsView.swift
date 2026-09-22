import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var dashboard: DashboardModel
  @AppStorage(SettingsKeys.weatherLocation) private var weatherLocation = SettingsKeys
    .defaultWeatherLocation
  @AppStorage(SettingsKeys.fillSecondaryDisplay) private var fillSecondaryDisplay = true
  @AppStorage(SettingsKeys.computerName) private var computerName = "Ken's M4 Mini"

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
        TextField("Town or city", text: $weatherLocation)
          .textFieldStyle(.roundedBorder)

        HStack {
          Text("Weather data is provided by Open-Meteo.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Refresh Weather") {
            dashboard.refresh(forceWeather: true)
          }
          .disabled(weatherLocation.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }

      Section("Privacy") {
        Text(
          "System and Copilot session status are read locally. AgentMon never sends project names, prompts, or code to the weather service."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding(12)
    .frame(width: 480, height: 370)
    .onSubmit {
      dashboard.refresh(forceWeather: true)
    }
  }
}
