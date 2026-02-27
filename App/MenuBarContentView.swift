import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @State private var didAppear = false
    @State private var settingsExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ASIAIR Sync")
                .font(.headline)

            statusBlock

            Divider()

            setupBlock

            if let feedback = model.startAtLoginFeedback {
                Divider()
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            updatesBlock

            Divider()

            Button("Quit ASIAIR Sync") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 380)
        .onAppear {
            if didAppear { return }
            didAppear = true
            settingsExpanded = model.loadSettingsExpandedPreference()
            model.maybePromptForStartAtLogin()
        }
        .alert("Enable Start at Login?", isPresented: $model.showStartAtLoginPrompt) {
            Button("Enable") {
                model.handleStartAtLoginChoice(enable: true)
            }
            Button("Not now", role: .cancel) {
                model.handleStartAtLoginChoice(enable: false)
            }
        } message: {
            Text("Run ASIAIR Sync automatically when you log into macOS?")
        }
        .alert("Update Available", isPresented: $model.showUpdateAvailablePrompt) {
            Button("Download") {
                model.openUpdateDownload()
            }
            Button("Later", role: .cancel) { }
        } message: {
            if let version = model.availableUpdateVersion {
                Text("Version v\(version) is available. Download page will open in your browser.")
            } else {
                Text("A new version is available.")
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text("Status")
                        .foregroundStyle(.secondary)
                    Text(model.phaseLabel)
                        .foregroundStyle(color(for: model.runtimeStatus.phase))
                }

                Spacer()

                Text("Speed \(model.runtimeStatus.transferSpeed ?? "—")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: model.runtimeStatus.progressPercent, total: 100)

            HStack {
                Text("Progress")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(model.runtimeStatus.progressPercent))%")
                    .monospacedDigit()
            }
            .font(.caption)

            HStack {
                Text("Files left")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.runtimeStatus.filesLeftToDownload)")
                    .monospacedDigit()
            }
            .font(.caption)
            .help("Estimated number of FITS files still pending download in the current sync cycle.")

            HStack {
                Text("Local FITS files")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.runtimeStatus.localFitsCount)")
                    .monospacedDigit()
            }
            .font(.caption)
            .help("Total FITS files currently present in your selected local destination folder.")

            if let lastSynced = model.runtimeStatus.lastSyncedAt {
                HStack {
                    Text("Last sync")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(lastSynced.formatted(.dateTime.year().month().day().hour().minute().second()))
                        .multilineTextAlignment(.trailing)
                }
                .font(.caption)
            }

            if let currentFile = model.runtimeStatus.currentFile, !currentFile.isEmpty {
                Text("Current: \(currentFile)")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .help(currentFile)
            }

            if model.runtimeStatus.phase == .error || model.runtimeStatus.phase == .notConfigured {
                Text(model.runtimeStatus.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.settings.normalized.isConfigured {
                Button(model.runtimeStatus.phase == .syncing || model.runtimeStatus.phase == .idle ? "Pause Sync" : "Resume Sync") {
                    model.pauseOrResume()
                }
            }
        }
    }

    private var setupBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Settings")
                    .font(.subheadline)
                    .bold()

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        settingsExpanded.toggle()
                        model.saveSettingsExpandedPreference(settingsExpanded)
                    }
                } label: {
                    Image(systemName: settingsExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .help(settingsExpanded ? "Collapse settings" : "Expand settings")
            }

            if settingsExpanded {
                HStack {
                    Text("Auth")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Guest")
                        .font(.caption)
                }

                TextField("ASIAIR host (e.g. 192.168.8.189)", text: $model.settings.host)
                    .textFieldStyle(.roundedBorder)

                TextField("Share name", text: $model.settings.shareName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Interval")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.settings.syncIntervalSeconds)s")
                        .monospacedDigit()
                    Stepper(value: $model.settings.syncIntervalSeconds, in: 5...3600, step: 5) {
                        EmptyView()
                    }
                    .labelsHidden()
                }

                Toggle("Delete local files removed on ASIAIR", isOn: $model.settings.deleteRemovedFiles)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Destination folder")
                        .foregroundStyle(.secondary)

                    Text(model.settings.destinationPath.isEmpty ? "No folder selected" : model.settings.destinationPath)
                        .font(.caption)
                        .foregroundStyle(model.settings.destinationPath.isEmpty ? .red : .secondary)
                        .lineLimit(2)

                    Button("Choose Folder") {
                        model.chooseDestinationFolder()
                    }
                }

                Button("Apply Settings & Start") {
                    model.applySettingsAndStart()
                }
                .disabled(!model.canApplySettings)
            }
        }
    }

    private var updatesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Updates")
                    .font(.subheadline)
                    .bold()

                Spacer()

                if model.isCheckingForUpdates {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(model.updateStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Check for Updates") {
                    model.checkForUpdates(userInitiated: true)
                }

                if model.availableUpdateVersion != nil {
                    Button("Download Update") {
                        model.openUpdateDownload()
                    }
                }
            }
        }
    }

    private func color(for phase: SyncPhase) -> Color {
        switch phase {
        case .notConfigured:
            return .orange
        case .paused:
            return .yellow
        case .syncing:
            return .blue
        case .idle:
            return .green
        case .error:
            return .red
        }
    }
}
