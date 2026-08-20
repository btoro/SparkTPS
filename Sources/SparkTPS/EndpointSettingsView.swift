import SwiftUI

struct EndpointSettingsView: View {
    @ObservedObject var monitor: MetricsMonitor
    @Binding var isExpanded: Bool
    @State private var draftEndpoint = ""
    @State private var draftIdleAlertMinutes = 10
    @State private var draftInputRate = 1.0
    @State private var draftOutputRate = 6.0

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
            Divider()
            Text("Cost estimate")
                .font(.caption.weight(.semibold))
            HStack {
                Text("Input $")
                TextField("1.00", value: $draftInputRate, format: .number)
                    .textFieldStyle(.roundedBorder)
                Text("Output $")
                TextField("6.00", value: $draftOutputRate, format: .number)
                    .textFieldStyle(.roundedBorder)
                Text("/ 1M")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            Text("Configure the input and output price per million tokens used for the estimate. Defaults are $1 input and $6 output.")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            draftInputRate = monitor.inputPricePerMillion
            draftOutputRate = monitor.outputPricePerMillion
        }
    }

    private func save() {
        monitor.saveEndpoint(draftEndpoint)
        monitor.saveIdleAlert(enabled: monitor.idleAlertEnabled, minutes: draftIdleAlertMinutes)
        monitor.savePricing(inputPerMillion: draftInputRate, outputPerMillion: draftOutputRate)
        isExpanded = false
    }
}
