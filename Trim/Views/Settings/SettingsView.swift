import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let photoService: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    @State private var showKeptPhotos = false
    @State private var showResetKeepsConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                // Appearance
                Section {
                    Picker("Appearance", selection: $settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: settings.appearanceMode) { settings.save() }
                } header: {
                    Text("Appearance")
                }

                // Session length
                Section {
                    Picker("Session length", selection: $settings.sessionLength) {
                        ForEach(SessionLength.allCases, id: \.self) { len in
                            Text(len.displayName).tag(len)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: settings.sessionLength) { settings.save() }
                } header: {
                    Text("Session length")
                } footer: {
                    Text("Number of photos per session for capped modes (Last night, Feeling lucky). Month & year, date range, and Pick up where I left off are unaffected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Undo steps
                Section {
                    Picker("Undo steps", selection: $settings.undoSteps) {
                        Text("1 step").tag(1)
                        Text("2 steps").tag(2)
                        Text("3 steps").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.undoSteps) { settings.save() }
                } header: {
                    Text("Undo")
                } footer: {
                    Text("How many undo steps are available per session. Resets at the start of each session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Keep exclusion
                Section {
                    Picker("Exclude kept photos for", selection: $settings.keepExclusion) {
                        ForEach(KeepExclusion.allCases, id: \.self) { opt in
                            Text(opt.displayName).tag(opt)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: settings.keepExclusion) { settings.save() }
                } header: {
                    Text("Keep exclusion")
                } footer: {
                    Text("How long photos marked Keep are excluded from future sessions. \"Forever-ever\" never shows them again. \"Never\" always includes them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // My Keeps
                Section {
                    Button("My Keeps") {
                        showKeptPhotos = true
                    }
                    .buttonStyle(.link)

                    let keepCount = settings.keptAssetIdentifiers.count
                    if keepCount > 0 {
                        Button("Reset all Keeps") {
                            showResetKeepsConfirmation = true
                        }
                        .buttonStyle(.link)
                        .foregroundStyle(.red)
                    }
                }

                // Date picker format
                Section {
                    Picker("Session date picker", selection: $settings.datePickerFormat) {
                        Text("Month & year").tag(DatePickerFormat.monthYear)
                        Text("Date range").tag(DatePickerFormat.dateRange)
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: settings.datePickerFormat) { settings.save() }
                } header: {
                    Text("Date picker")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 420, height: 580)
        .confirmationDialog(
            "Reset all Keeps?",
            isPresented: $showResetKeepsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                settings.clearAllKeeps()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let count = settings.keptAssetIdentifiers.count
            Text("Remove Keep status from all \(count) photo\(count == 1 ? "" : "s")? They'll re-enter your triage pool.")
        }
        .sheet(isPresented: $showKeptPhotos) {
            NavigationStack {
                KeptPhotosView(settings: settings, photoService: photoService)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showKeptPhotos = false }
                        }
                    }
            }
            .frame(width: 600, height: 500)
        }
    }
}
