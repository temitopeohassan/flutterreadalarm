import Flutter
import UIKit
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import AppIntents
import SwiftUI
#endif

/// Reading alarms on iOS: the same "readalarm/alarms" channel as Android's
/// AlarmEngine.kt, so the Dart side is shared.
///
/// - iOS 26+, once allowed: a real alarm (AlarmKit). It rings like the
///   Clock app, through silent mode and Focus, even if ReadAlarm was
///   closed. "Read" on the alarm opens ReadAlarm. A silent notification
///   comes with it, to open ReadAlarm from and to tell when it rang.
/// - Otherwise: a notification with a 30-second alarm sound, repeated
///   every 30 seconds for two and a half minutes. Notifications ring even
///   when ReadAlarm is closed, but follow silent mode.
///
/// iOS keeps both after the app is closed and after a restart, so nothing
/// needs putting back.
final class AlarmEngine: NSObject, FlutterPlugin, UNUserNotificationCenterDelegate {
  static let shared = AlarmEngine()

  private static let prefix = "readalarm."
  private static let soundName = "readalarm_alarm.wav"
  private static let category = "READALARM"
  private static let burstCount = 4
  private static let burstGap: TimeInterval = 30
  /// iOS keeps at most 64 scheduled notifications per app.
  private static let notificationBudget = 60

  private var channel: FlutterMethodChannel?
  private weak var previousDelegate: UNUserNotificationCenterDelegate?
  private var pendingLaunch: [String: Any]?
  private var dartReady = false
  private let defaults = UserDefaults.standard
  private let center = UNUserNotificationCenter.current()

  // MARK: Setup

  /// Called first thing at launch, so a tap on an alarm that opened the
  /// app reaches us.
  func attach() {
    if center.delegate !== self {
      previousDelegate = center.delegate
      center.delegate = self
    }
    let start = UNNotificationAction(identifier: "start", title: "Start reading", options: [.foreground])
    let snooze = UNNotificationAction(identifier: "snooze", title: "Snooze 10 min", options: [])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: Self.category, actions: [start, snooze], intentIdentifiers: [], options: []),
    ])
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.planRepeats() }
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let engine = AlarmEngine.shared
    // Plugins may have taken the notification delegate: take it back,
    // passing on what isn't ours.
    engine.attach()
    engine.installSound(registrar)
    let alarms = FlutterMethodChannel(name: "readalarm/alarms", binaryMessenger: registrar.messenger())
    engine.channel = alarms
    alarms.setMethodCallHandler { call, result in engine.handle(call, result) }
    let diagnostics = FlutterMethodChannel(name: "readalarm/diagnostics", binaryMessenger: registrar.messenger())
    diagnostics.setMethodCallHandler { call, result in engine.handleDiagnostics(call, result) }
  }

  /// Notification sounds must be in Library/Sounds: copy ours there from
  /// the Flutter assets.
  private func installSound(_ registrar: FlutterPluginRegistrar) {
    let fm = FileManager.default
    guard let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
    let dir = library.appendingPathComponent("Sounds")
    let target = dir.appendingPathComponent(Self.soundName)
    if fm.fileExists(atPath: target.path) { return }
    let key = registrar.lookupKey(forAsset: "assets/sounds/\(Self.soundName)")
    guard let source = Bundle.main.path(forResource: key, ofType: nil) else {
      log("Alarm sound not found in the app")
      return
    }
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    do {
      try fm.copyItem(atPath: source, toPath: target.path)
    } catch {
      log("Couldn't install the alarm sound: \(error.localizedDescription)")
    }
  }

  // MARK: Channel

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let ids = (args["ids"] as? [NSNumber] ?? []).map { $0.intValue }
    switch call.method {
    case "set":
      for m in args["entries"] as? [[String: Any]] ?? [] {
        if let e = Entry(map: m) { set(e) }
      }
      planRepeats()
      result(nil)
    case "cancel":
      cancel(ids)
      result(nil)
    case "dismiss":
      dismiss(ids)
      result(nil)
    case "pending":
      result(stored().map { $0.payload })
    case "registered":
      registered(ids, result)
    case "takeLaunch":
      takeLaunch(result)
    case "closeApp":
      // As a phone might: so the alarm test checks an alarm rings with
      // ReadAlarm closed. (Internal testing only: the App Store doesn't
      // allow apps to close themselves.)
      log("Alarm test: closing the app")
      result(nil)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    case "permissions":
      permissions(result)
    case "requestPermission":
      requestPermission(args["key"] as? String ?? "", result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Stored alarms

  /// One ring, as Android's AlarmEngine.Entry: [weekday] 1–7 (Monday–
  /// Sunday) repeats weekly at [hour]:[minute]; 0 rings once at [at].
  struct Entry: Codable {
    let id: Int
    let weekday: Int
    let hour: Int
    let minute: Int
    let at: Int64
    let payload: String
    let title: String
    let body: String

    init?(map m: [String: Any]) {
      guard let id = (m["id"] as? NSNumber)?.intValue, let payload = m["payload"] as? String else { return nil }
      self.id = id
      weekday = (m["weekday"] as? NSNumber)?.intValue ?? 0
      hour = (m["hour"] as? NSNumber)?.intValue ?? 0
      minute = (m["minute"] as? NSNumber)?.intValue ?? 0
      at = (m["at"] as? NSNumber)?.int64Value ?? 0
      self.payload = payload
      title = m["title"] as? String ?? "Time to read"
      body = m["body"] as? String ?? ""
    }

    var weekly: Bool { weekday != 0 }

    /// Apple's weekday: 1 = Sunday … 7 = Saturday.
    var appleWeekday: Int { weekday % 7 + 1 }

    func nextRing(after now: Date = Date()) -> Date? {
      if !weekly {
        let date = Date(timeIntervalSince1970: TimeInterval(at) / 1000)
        return date > now ? date : nil
      }
      var c = DateComponents()
      c.weekday = appleWeekday
      c.hour = hour
      c.minute = minute
      c.second = 0
      return Calendar.current.nextDate(after: now, matching: c, matchingPolicy: .nextTime)
    }
  }

  private func stored() -> [Entry] {
    let all = defaults.dictionary(forKey: "readalarm_alarms") as? [String: Data] ?? [:]
    return all.values.compactMap { try? JSONDecoder().decode(Entry.self, from: $0) }
  }

  private func save(_ e: Entry?, id: Int) {
    var all = defaults.dictionary(forKey: "readalarm_alarms") as? [String: Data] ?? [:]
    all["\(id)"] = e.flatMap { try? JSONEncoder().encode($0) }
    defaults.set(all, forKey: "readalarm_alarms")
  }

  private func entry(_ id: Int) -> Entry? { stored().first { $0.id == id } }

  // MARK: Scheduling

  private func set(_ e: Entry) {
    guard let next = e.nextRing() else {
      cancel([e.id])
      log("Alarm \(e.id) has no future ring: removed")
      return
    }
    save(e, id: e.id)
    let system = systemAlarmsAllowed()
    setLoud(e.id, !system)
    addNotification(e, loud: !system)
    if system { scheduleSystemAlarm(e) }
    log("Alarm \(e.id) set for \(next)" + (system ? " (system alarm)" : " (notification)"))
  }

  private func addNotification(_ e: Entry, loud: Bool) {
    center.add(request(e, identifier: Self.prefix + "\(e.id)", trigger: trigger(e), loud: loud)) { error in
      if let error = error { self.log("ERROR alarm \(e.id) not set: \(error.localizedDescription)") }
    }
  }

  /// Alarms that ring by notification (no system alarm), which get repeats.
  private func loudIds() -> Set<Int> {
    Set((defaults.array(forKey: "readalarm_loud") as? [Int]) ?? [])
  }

  private func setLoud(_ id: Int, _ loud: Bool) {
    var ids = loudIds()
    if loud { ids.insert(id) } else { ids.remove(id) }
    defaults.set(Array(ids), forKey: "readalarm_loud")
  }

  private func trigger(_ e: Entry) -> UNCalendarNotificationTrigger {
    if e.weekly {
      var c = DateComponents()
      c.weekday = e.appleWeekday
      c.hour = e.hour
      c.minute = e.minute
      return UNCalendarNotificationTrigger(dateMatching: c, repeats: true)
    }
    let date = Date(timeIntervalSince1970: TimeInterval(e.at) / 1000)
    return once(date)
  }

  private func once(_ date: Date) -> UNCalendarNotificationTrigger {
    let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return UNCalendarNotificationTrigger(dateMatching: c, repeats: false)
  }

  private func request(_ e: Entry, identifier: String, trigger: UNNotificationTrigger, loud: Bool) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = e.title
    content.body = loud ? e.body : (e.body.isEmpty ? "Tap to start reading" : "\(e.body) · Tap to start reading")
    content.categoryIdentifier = Self.category
    content.userInfo = ["readalarm": e.id, "payload": e.payload]
    if loud {
      content.sound = soundInstalled ? UNNotificationSound(named: UNNotificationSoundName(Self.soundName)) : .default
    }
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .timeSensitive
    }
    return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
  }

  private var soundInstalled: Bool {
    guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return false }
    return FileManager.default.fileExists(atPath: library.appendingPathComponent("Sounds/\(Self.soundName)").path)
  }

  private func cancel(_ ids: [Int]) {
    let names = ids.flatMap { identifiers($0) }
    center.removePendingNotificationRequests(withIdentifiers: names)
    center.removeDeliveredNotifications(withIdentifiers: names)
    for id in ids {
      cancelSystemAlarm(id)
      save(nil, id: id)
      setLoud(id, false)
    }
  }

  /// The alarm's notification and its repeats.
  private func identifiers(_ id: Int) -> [String] {
    [Self.prefix + "\(id)"] + (1...Self.burstCount).map { Self.prefix + "\(id).r\($0)" }
  }

  /// Stops the ringing: removes the shown notification and the repeats
  /// still to come (the alarm itself stays set).
  private func dismiss(_ ids: [Int]) {
    center.removeDeliveredNotifications(withIdentifiers: ids.flatMap { identifiers($0) })
    center.removePendingNotificationRequests(withIdentifiers: ids.flatMap { identifiers($0).dropFirst() })
    for id in ids { stopSystemAlarm(id) }
  }

  /// A notification sound lasts at most 30 seconds, so the next ring of
  /// each loud alarm is repeated every 30 seconds after it. Only the next
  /// ring: iOS keeps 64 notifications per app, and this is planned again
  /// whenever ReadAlarm opens.
  private func planRepeats() {
    center.getPendingNotificationRequests { pending in
      let repeats = pending.map { $0.identifier }.filter { $0.hasPrefix(Self.prefix) && $0.contains(".r") }
      self.center.removePendingNotificationRequests(withIdentifiers: repeats)
      var budget = Self.notificationBudget - (pending.count - repeats.count)
      let now = Date()
      let loudIds = self.loudIds()
      let loud = self.stored().filter { loudIds.contains($0.id) }
        .compactMap { e in e.nextRing(after: now).map { (e, $0) } }
        .sorted { $0.1 < $1.1 }
      for (e, ring) in loud {
        guard budget >= Self.burstCount else { break }
        for k in 1...Self.burstCount {
          let at = ring.addingTimeInterval(Self.burstGap * Double(k))
          self.center.add(self.request(e, identifier: Self.prefix + "\(e.id).r\(k)", trigger: self.once(at), loud: true))
        }
        budget -= Self.burstCount
      }
    }
  }

  private func registered(_ ids: [Int], _ result: @escaping FlutterResult) {
    center.getPendingNotificationRequests { pending in
      let names = Set(pending.map { $0.identifier })
      let held = ids.map { names.contains(Self.prefix + "\($0)") || self.hasSystemAlarm($0) }
      DispatchQueue.main.async { result(held) }
    }
  }

  // MARK: Ringing

  /// The alarm went off while ReadAlarm was on screen.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard let id = alarmId(notification) else {
      if let previous = previousDelegate,
         previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
        previous.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
      } else {
        completionHandler([.sound, .badge, .list, .banner])
      }
      return
    }
    log("Alarm \(id) rang, ReadAlarm open")
    markReported(notification)
    completionHandler([.sound, .list, .banner])
    deliver(notification, action: "open", cold: false)
  }

  /// The user tapped the alarm's notification or one of its buttons.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let notification = response.notification
    guard let id = alarmId(notification) else {
      if let previous = previousDelegate,
         previous.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
        previous.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
      } else {
        completionHandler()
      }
      return
    }
    let cold = UIApplication.shared.applicationState != .active
    markReported(notification)
    switch response.actionIdentifier {
    case "snooze":
      snooze(id)
    case "start":
      log("Alarm \(id): Start reading")
      dismiss([id])
      deliver(notification, action: "start", cold: cold)
    default:
      log("Alarm \(id) opened" + (cold ? " (ReadAlarm was closed)" : ""))
      deliver(notification, action: "open", cold: cold)
    }
    completionHandler()
  }

  private func alarmId(_ n: UNNotification) -> Int? {
    guard n.request.identifier.hasPrefix(Self.prefix) else { return nil }
    return (n.request.content.userInfo["readalarm"] as? NSNumber)?.intValue
  }

  private func snooze(_ id: Int) {
    log("Alarm \(id) snoozed")
    dismiss([id])
    let snoozeId = id - id % 10 + 8
    guard let e = entry(id) ?? entry(snoozeId) else { return }
    let at = Int64(Date().addingTimeInterval(10 * 60).timeIntervalSince1970 * 1000)
    var m: [String: Any] = ["id": snoozeId, "weekday": 0, "hour": 0, "minute": 0, "at": at]
    m["payload"] = e.payload
    m["title"] = e.title
    m["body"] = e.body
    if let snoozed = Entry(map: m) { set(snoozed) }
    planRepeats()
  }

  private func deliver(_ n: UNNotification, action: String, cold: Bool) {
    guard let payload = n.request.content.userInfo["payload"] as? String else { return }
    send([
      "payload": payload, "action": action, "cold": cold,
      "rangAt": Int64(n.date.timeIntervalSince1970 * 1000),
    ])
  }

  private func send(_ launch: [String: Any]) {
    DispatchQueue.main.async {
      if self.dartReady, let channel = self.channel {
        channel.invokeMethod("launch", arguments: launch)
      } else {
        self.pendingLaunch = launch
      }
    }
  }

  /// The alarm that opened the app. If none was tapped, an alarm that rang
  /// in the last 10 minutes while ReadAlarm was closed counts, as when
  /// Android opens ReadAlarm at the alarm time.
  private func takeLaunch(_ result: @escaping FlutterResult) {
    dartReady = true
    if let launch = pendingLaunch {
      pendingLaunch = nil
      return result(launch)
    }
    center.getDeliveredNotifications { delivered in
      let recent = delivered
        .filter { self.alarmId($0) != nil && !self.isReported($0) && $0.date > Date().addingTimeInterval(-600) }
        .max { $0.date < $1.date }
      DispatchQueue.main.async {
        guard let n = recent, let payload = n.request.content.userInfo["payload"] as? String else {
          return result(nil)
        }
        self.markReported(n)
        self.log("Alarm \(self.alarmId(n) ?? -1) rang while ReadAlarm was closed")
        result([
          "payload": payload, "action": "open", "cold": true,
          "rangAt": Int64(n.date.timeIntervalSince1970 * 1000),
        ])
      }
    }
  }

  private func reportKey(_ n: UNNotification) -> String {
    "\(n.request.identifier.components(separatedBy: ".r").first ?? "")@\(Int(n.date.timeIntervalSince1970 / 120))"
  }

  private func isReported(_ n: UNNotification) -> Bool {
    (defaults.stringArray(forKey: "readalarm_reported") ?? []).contains(reportKey(n))
  }

  private func markReported(_ n: UNNotification) {
    let list = (defaults.stringArray(forKey: "readalarm_reported") ?? []).suffix(50) + [reportKey(n)]
    defaults.set(Array(list), forKey: "readalarm_reported")
  }

  /// "Read" on a system alarm (iOS 26+).
  func openedFromSystemAlarm(_ id: Int) {
    let cold = UIApplication.shared.applicationState != .active
    log("Alarm \(id): Read tapped on the system alarm")
    center.getDeliveredNotifications { delivered in
      let n = delivered.filter { self.alarmId($0) == id }.max { $0.date < $1.date }
      if let n = n {
        self.markReported(n)
        self.deliver(n, action: "open", cold: cold)
      } else if let e = self.entry(id) {
        self.send(["payload": e.payload, "action": "open", "cold": cold])
      }
    }
  }

  // MARK: System alarms (AlarmKit, iOS 26+)

  private static func uuid(_ id: Int) -> UUID {
    UUID(uuidString: String(format: "52454144-414c-4152-4d00-%012llx", UInt64(id)))!
  }

  private func systemAlarmsAllowed() -> Bool {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      return AlarmManager.shared.authorizationState == .authorized
    }
    #endif
    return false
  }

  private func hasSystemAlarm(_ id: Int) -> Bool {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      let alarms = (try? AlarmManager.shared.alarms) ?? []
      return alarms.contains { $0.id == Self.uuid(id) }
    }
    #endif
    return false
  }

  /// Sets [e] as a system alarm. If iOS refuses, its notification rings
  /// instead.
  private func scheduleSystemAlarm(_ e: Entry) {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      let id = Self.uuid(e.id)
      try? AlarmManager.shared.cancel(id: id)
      let schedule: Alarm.Schedule
      if e.weekly {
        let days: [Locale.Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        schedule = .relative(.init(
          time: .init(hour: e.hour, minute: e.minute),
          repeats: .weekly([days[e.weekday - 1]])
        ))
      } else {
        schedule = .fixed(Date(timeIntervalSince1970: TimeInterval(e.at) / 1000))
      }
      let alert = AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: e.title),
        stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle"),
        secondaryButton: AlarmButton(text: "Read", textColor: .white, systemImageName: "book"),
        secondaryButtonBehavior: .custom
      )
      let attributes = AlarmAttributes<ReadAlarmMetadata>(
        presentation: AlarmPresentation(alert: alert),
        metadata: ReadAlarmMetadata(),
        tintColor: Color.orange
      )
      let configuration = AlarmManager.AlarmConfiguration<ReadAlarmMetadata>(
        countdownDuration: nil,
        schedule: schedule,
        attributes: attributes,
        secondaryIntent: OpenReadAlarmIntent(alarmId: e.id)
      )
      Task {
        do {
          _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        } catch {
          self.log("System alarm \(e.id) refused (\(error.localizedDescription)): ringing by notification")
          self.setLoud(e.id, true)
          self.addNotification(e, loud: true)
          self.planRepeats()
        }
      }
    }
    #endif
  }

  private func cancelSystemAlarm(_ id: Int) {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) { try? AlarmManager.shared.cancel(id: Self.uuid(id)) }
    #endif
  }

  private func stopSystemAlarm(_ id: Int) {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) { try? AlarmManager.shared.stop(id: Self.uuid(id)) }
    #endif
  }

  // MARK: Permissions

  /// notifications: allowed. alarms: system alarms allowed (true before
  /// iOS 26, which has none to ask for).
  private func permissions(_ result: @escaping FlutterResult) {
    center.getNotificationSettings { settings in
      let notifications = settings.authorizationStatus == .authorized
        || settings.authorizationStatus == .provisional
      var alarms = true
      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) { alarms = AlarmManager.shared.authorizationState == .authorized }
      #endif
      DispatchQueue.main.async { result(["notifications": notifications, "alarms": alarms]) }
    }
  }

  private func requestPermission(_ key: String, _ result: @escaping FlutterResult) {
    switch key {
    case "notifications":
      center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        DispatchQueue.main.async { result(granted) }
      }
    case "alarms":
      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        Task {
          let state = (try? await AlarmManager.shared.requestAuthorization()) ?? .denied
          let granted = state == .authorized
          self.log("System alarms " + (granted ? "allowed" : "not allowed"))
          if granted {
            // Move existing alarms onto system alarms.
            for e in self.stored() { self.set(e) }
            self.planRepeats()
          } else if state == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
            await UIApplication.shared.open(url)
          }
          DispatchQueue.main.async { result(granted) }
        }
        return
      }
      #endif
      result(true)
    default:
      result(nil)
    }
  }

  // MARK: Log and diagnostics

  func log(_ message: String) {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    var lines = defaults.stringArray(forKey: "readalarm_engine_log") ?? []
    lines.append("\(f.string(from: Date())) \(message)")
    defaults.set(Array(lines.suffix(300)), forKey: "readalarm_engine_log")
  }

  private func handleDiagnostics(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "phone":
      phoneReport(result)
    case "registered":
      registered((args["ids"] as? [NSNumber] ?? []).map { $0.intValue }, result)
    case "logcat":
      result("(No system log on iPhone.)")
    case "email", "share":
      // The share sheet covers Mail, WhatsApp and the rest.
      let shared = share(args["body"] as? String ?? "", subject: args["subject"] as? String ?? "")
      result(call.method == "email" ? (shared ? "share" : nil) : shared)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func share(_ text: String, subject: String) -> Bool {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    guard var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return false }
    while let presented = top.presentedViewController { top = presented }
    let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    sheet.setValue(subject, forKey: "subject")
    sheet.popoverPresentationController?.sourceView = top.view
    sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
    top.present(sheet, animated: true)
    return true
  }

  private func phoneReport(_ result: @escaping FlutterResult) {
    center.getNotificationSettings { settings in
      self.center.getPendingNotificationRequests { pending in
        let device = UIDevice.current
        var lines = ["PHONE", "\(device.model), \(device.systemName) \(device.systemVersion)", ""]
        lines.append("APP")
        let info = Bundle.main.infoDictionary ?? [:]
        lines.append("ReadAlarm \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))")
        lines.append("")
        lines.append("WHAT CAN STOP ALARMS")
        lines.append("Notifications: \(Self.describe(settings.authorizationStatus))")
        lines.append("Notification sound: \(settings.soundSetting == .enabled ? "on" : "off")")
        if #available(iOS 15.0, *) {
          lines.append("Time-sensitive: \(settings.timeSensitiveSetting == .enabled ? "allowed" : "not allowed")")
        }
        lines.append("System alarms (iOS 26+): " + self.systemAlarmStatus())
        lines.append("Alarm sound installed: \(self.soundInstalled)")
        lines.append("")
        lines.append("ALARMS HELD BY THE ALARM ENGINE")
        let ours = Set(pending.map { $0.identifier })
        let f = DateFormatter()
        f.dateFormat = "EEE yyyy-MM-dd HH:mm"
        let list = self.stored()
        if list.isEmpty { lines.append("No alarms stored.") }
        for e in list {
          let next = e.nextRing().map { f.string(from: $0) } ?? "none"
          let kind = e.weekly ? "weekly day \(e.weekday) \(e.hour):\(String(format: "%02d", e.minute))" : "once"
          lines.append("\(e.id): \(kind), next \(next), notification set: \(ours.contains(Self.prefix + "\(e.id)")), "
            + "system alarm: \(self.hasSystemAlarm(e.id)), \"\(e.title)\"")
        }
        lines.append("Scheduled notifications: \(pending.count) of 64")
        lines.append("")
        lines.append("ALARM ENGINE LOG (whether alarms fired)")
        let log = self.defaults.stringArray(forKey: "readalarm_engine_log") ?? []
        lines.append(log.isEmpty ? "Nothing yet." : log.joined(separator: "\n"))
        DispatchQueue.main.async { result(lines.joined(separator: "\n")) }
      }
    }
  }

  private func systemAlarmStatus() -> String {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      switch AlarmManager.shared.authorizationState {
      case .authorized: return "allowed"
      case .denied: return "not allowed (Settings → ReadAlarm → Alarms)"
      default: return "not asked yet"
      }
    }
    #endif
    return "not on this iOS version (notifications ring instead)"
  }

  private static func describe(_ s: UNAuthorizationStatus) -> String {
    switch s {
    case .authorized: return "allowed"
    case .denied: return "NOT allowed"
    case .provisional: return "quiet only"
    case .notDetermined: return "not asked yet"
    default: return "allowed for a while"
    }
  }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct ReadAlarmMetadata: AlarmMetadata {}

/// "Read" on the system alarm: opens ReadAlarm on that alarm.
@available(iOS 26.0, *)
struct OpenReadAlarmIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Read now"
  static var description = IntentDescription("Opens ReadAlarm to start reading.")
  static var openAppWhenRun = true

  @Parameter(title: "Alarm")
  var alarmId: Int

  init() {}

  init(alarmId: Int) {
    self.alarmId = alarmId
  }

  func perform() async throws -> some IntentResult {
    let id = alarmId
    await MainActor.run { AlarmEngine.shared.openedFromSystemAlarm(id) }
    return .result()
  }
}
#endif
