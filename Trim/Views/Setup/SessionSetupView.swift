import SwiftUI

struct SessionSetupView: View {
    @Bindable var settings: AppSettings
    let photoService: PhotoLibraryService
    let hasSavedState: Bool
    let hasPhotos: Bool
    let libraryIsEmpty: Bool
    let onStart: (SessionMode) -> Void

    // Month & year picker state
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int  = Calendar.current.component(.year, from: Date())
    // Date range picker state
    @State private var rangeStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var rangeEnd: Date   = Date()
    // UI
    @State private var showingSettings = false
    @State private var lastNightAvailable: Bool = false

    private let cardHeight: CGFloat = 90

    var body: some View {
        VStack(spacing: 0) {
            // Title bar — centered title, gear pinned to trailing
            ZStack {
                Text("Trim")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity)
                HStack {
                    Spacer()
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 24)

            if libraryIsEmpty {
                emptyLibraryView
            } else {
                sessionModes
            }

            Spacer()

            // Lifetime stats footer
            if settings.totalFilesDeleted > 0 {
                lifetimeStatsFooter
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }
        }
        .onAppear { checkLastNightAvailability() }
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings, photoService: photoService)
                .onDisappear { checkLastNightAvailability() }
        }
    }

    // MARK: - Empty library

    private var emptyLibraryView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Looking trim.")
                .font(.system(size: 28, weight: .black, design: .rounded))
            Text("Your photo library is empty.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Session modes

    private var sessionModes: some View {
        VStack(spacing: 12) {
            // Pick up where I left off (only if saved state exists)
            if hasSavedState {
                modeCard(
                    title: "Pick up where I left off",
                    subtitle: "Resume your last session",
                    iconName: "arrow.clockwise",
                    color: .blue
                ) { onStart(.pickUpWhereILeftOff) }
            }

            // Last night wasn't a movie (only if qualifying photos exist)
            if lastNightAvailable {
                modeCard(
                    title: "Last night wasn't a movie",
                    subtitle: "Review last night and assess the damage",
                    iconName: "moon.stars",
                    color: .purple
                ) { onStart(.lastNight) }
            }

            // I'm feeling frisky
            modeCard(
                title: "I'm feeling frisky",
                subtitle: "A random corner of your library, hopefully we don't land on any noods",
                iconName: "dice",
                color: .orange
            ) { onStart(.feelingLucky) }

            // Doom Scroll
            modeCard(
                title: "Doom Scroll",
                subtitle: "Scroll endlessly to your heart's content.",
                iconName: "infinity",
                color: .red
            ) { onStart(.doomScroll) }

            // Month picker or date range
            if settings.datePickerFormat == .monthYear {
                monthYearPicker
            } else {
                dateRangePicker
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Lifetime stats footer

    private var lifetimeStatsFooter: some View {
        HStack {
            Spacer()
            Text(lifetimeStatsText)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var lifetimeStatsText: String {
        let files = settings.totalFilesDeleted
        let bytes = settings.totalBytesFreed
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        let bytesStr = formatter.string(fromByteCount: bytes)
        return "All time: \(files.formatted()) file\(files == 1 ? "" : "s") trimmed · \(bytesStr) saved"
    }

    // MARK: - Mode card

    private func modeCard(
        title: String,
        subtitle: String,
        iconName: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 32))
                    .foregroundStyle(color)
                    .frame(width: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: cardHeight)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var monthYearPicker: some View {
        HStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 32))
                .foregroundStyle(.teal)
                .frame(width: 52)

            Text("By month")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            Picker("Month", selection: $selectedMonth) {
                ForEach(1...12, id: \.self) { m in
                    Text(monthName(m)).tag(m)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(maxWidth: 130)

            Picker("Year", selection: $selectedYear) {
                ForEach(availableYears, id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(maxWidth: 90)

            Button("Explore") {
                onStart(.monthYear(month: selectedMonth, year: selectedYear))
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: cardHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var dateRangePicker: some View {
        HStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32))
                .foregroundStyle(.teal)
                .frame(width: 52)

            Text("Date range")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                .labelsHidden()
                .controlSize(.large)

            Text("–")
                .foregroundStyle(.secondary)

            DatePicker("To", selection: $rangeEnd, displayedComponents: .date)
                .labelsHidden()
                .controlSize(.large)

            Button("Explore") {
                onStart(.dateRange(start: rangeStart, end: rangeEnd))
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: cardHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func checkLastNightAvailability() {
        let service = photoService
        let capturedSettings = settings
        Task.detached(priority: .userInitiated) {
            let available = service.hasLastNightPhotos(settings: capturedSettings)
            await MainActor.run { lastNightAvailable = available }
        }
    }

    private var availableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array(stride(from: current, through: 2000, by: -1))
    }

    private func monthName(_ m: Int) -> String {
        DateFormatter().monthSymbols[m - 1]
    }
}
