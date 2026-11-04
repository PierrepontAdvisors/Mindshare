import AppKit
import Combine
import MemoryCore
import ServiceManagement
import UserNotifications

private let limitsKey = "limitsGB"
private let refreshKey = "refreshSeconds"

final class Monitor: ObservableObject {
    @Published private(set) var rows: [AppUsage] = []
    @Published private(set) var limitsGB: [String: Int]
    @Published private(set) var notificationsOff = false
    @Published private(set) var refreshSeconds: Int
    @Published private(set) var system: SystemMemory?
    @Published private(set) var menuBarIcon = NSImage()
    @Published private(set) var menuBarLabel = "Mindshare"
    @Published private(set) var peaks: [String: UInt64] = [:]
    @Published private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled

    let icons = AppIcons()

    private var warned: Set<String> = []
    private var shownStatus: MenuBarStatus?
    private var ticker: AnyCancellable?
    private var quitWatcher: AnyCancellable?

    var isAnyOverLimit: Bool { rows.contains { isOverLimit($0, limitsGB: limitsGB) } }

    init() {
        limitsGB = UserDefaults.standard.dictionary(forKey: limitsKey) as? [String: Int] ?? [:]
        refreshSeconds = validRefreshSeconds(UserDefaults.standard.integer(forKey: refreshKey))
        requestNotificationPermission()
        refresh()
        startTicker()
        // Event-driven, so a quit app leaves the list at once without any extra polling.
        quitWatcher = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] _ in self?.refresh() }
    }

    func setOpensAtLogin(_ isOn: Bool) {
        let service = SMAppService.mainApp
        do {
            try isOn ? service.register() : service.unregister()
        } catch {
            NSLog("Mindshare: could not change login item: %@", error.localizedDescription)
        }
        opensAtLogin = service.status == .enabled
        // macOS can accept the request but still want approval, so take the user to where they can give it.
        if isOn && !opensAtLogin { SMAppService.openSystemSettingsLoginItems() }
    }

    func setRefreshSeconds(_ seconds: Int) {
        refreshSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: refreshKey)
        startTicker()
    }

    private func startTicker() {
        let interval = TimeInterval(refreshSeconds)
        // Tolerance lets macOS batch these wake-ups with others, which saves energy. .common keeps sampling while a menu is open.
        ticker = Timer.publish(every: interval, tolerance: interval * 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func setLimit(_ gb: Int?, for id: String) {
        let updated = limitsGB.filter { $0.key != id }.merging(gb.map { [id: $0] } ?? [:]) { $1 }
        limitsGB = updated
        UserDefaults.standard.set(updated, forKey: limitsKey)
        refresh()
    }

    /// A normal quit lets apps ask to save unfinished work. Force quit is for frozen apps and loses anything unsaved.
    func quit(_ row: AppUsage, force: Bool = false) {
        let apps = row.appPIDs.compactMap(NSRunningApplication.init(processIdentifier:))
        for app in apps where !(force ? app.forceTerminate() : app.terminate()) {
            NSLog("Mindshare: %@ did not accept the quit request", row.name)
        }
    }

    private func refresh() {
        let usage = groupByApp(sampleProcesses())
        let result = checkLimits(usage: usage, limitsGB: limitsGB, warned: warned)
        warned = result.warned
        result.newlyOver.forEach(sendWarning)
        peaks = updatedPeaks(peaks, rows: usage)
        rows = visibleRows(usage, limitsGB: limitsGB)
        system = readSystemMemory()
        updateMenuBar()
        updateNotificationStatus()
    }

    private func updateMenuBar() {
        let status = menuBarStatus(
            usedBytes: system?.usedBytes ?? 0,
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            state: system?.state ?? .unknown,
            anyOverLimit: isAnyOverLimit
        )
        // Checked separately: an app can go over its limit while the icon stays amber.
        let overLimit = isAnyOverLimit ? ", an app is over its limit" : ""
        let label = "Mindshare. \((system?.state ?? .unknown).label)\(overLimit)"
        if label != menuBarLabel { menuBarLabel = label }
        guard status != shownStatus else { return }
        shownStatus = status
        menuBarIcon = menuBarImage(status)
    }

    func openNotificationSettings() {
        guard let id = Bundle.main.bundleIdentifier,
              let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Mindshare: notification permission failed: %@", error.localizedDescription) }
        }
    }

    // Read on every refresh, so turning notifications on in System Settings shows up without a restart.
    private func updateNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let isOff = settings.authorizationStatus != .authorized
            DispatchQueue.main.async {
                if self?.notificationsOff != isOff { self?.notificationsOff = isOff }
            }
        }
    }

    private func sendWarning(_ row: AppUsage) {
        let content = UNMutableNotificationContent()
        content.title = "\(row.name) is over its limit"
        content.body = "Using \(memoryText(row.bytes)). Your limit is \(limitsGB[row.id] ?? 0) GB."
        content.sound = .default
        let request = UNNotificationRequest(identifier: row.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            guard let error else { return }
            NSLog("Mindshare: warning for %@ failed: %@", row.name, error.localizedDescription)
        }
    }
}
