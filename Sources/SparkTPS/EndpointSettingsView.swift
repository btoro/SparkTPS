import SwiftUI

struct EndpointSettingsView: View {
    @ObservedObject var monitor: MetricsMonitor
    @Binding var isExpanded: Bool
    @State private var draftEndpoint = ""
    @State private var draftIdleAlertMinutes = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metrics endpoint")
                .font(.caption.weight(.semibold))
            TextField("http://spark-host:8000/metrics", text: $draftEndpoint)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Text("Use the SGLang or vLLM /metrics URL reachable through your tailnet. No inference API key is needed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Divider()
            Stepper(
                "Alert after \(draftIdleAlertMinutes) minute\(draftIdleAlertMinutes == 1 ? "" : "s")",
                value: $draftIdleAlertMinutes,
                in: 1...120
            )
            .disabled(!monitor.idleAlertEnabled)
            if !monitor.idleAlertEnabled {
                Text("Idle alert is off. Use the bell at the top of the menu to enable it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Save & Connect", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            draftEndpoint = monitor.endpoint
            draftIdleAlertMinutes = monitor.idleAlertMinutes
        }
    }

    private func save() {
        monitor.saveEndpoint(draftEndpoint)
        monitor.saveIdleAlert(enabled: monitor.idleAlertEnabled, minutes: draftIdleAlertMinutes)
        isExpanded = false
    }
}
