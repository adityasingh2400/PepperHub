@preconcurrency import UserNotifications
import SwiftData
import Foundation

final class NotificationScheduler {

    static let doseReminderCategory = "DOSE_REMINDER"

    // Register notification categories + actions. Call once at app launch.
    static func registerCategories() {
        let markDosed = UNNotificationAction(
            identifier: "MARK_DOSED",
            title: "Mark as Dosed",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: "SNOOZE_15",
            title: "Snooze 15 min",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: doseReminderCategory,
            actions: [markDosed, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted
    }

    // Schedule dose reminders for the next N days based on active protocol.
    // Removes all previous peptide reminders first.
    // Marked @MainActor because LocalProtocolCompound is a SwiftData @Model bound
    // to the main-actor-isolated ModelContext that owns it.
    @MainActor
    static func reschedule(compounds: [LocalProtocolCompound], timezone: TimeZone) async {
        let center = UNUserNotificationCenter.current()

        // Remove all existing dose reminders
        let pending = await center.pendingNotificationRequests()
        let ids = pending.filter { $0.content.categoryIdentifier == doseReminderCategory }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: ids)

        let dailyDoseCount = compounds.reduce(0) { $0 + $1.doseTimes.count }
        guard dailyDoseCount > 0 else { return }
        let horizonDays = max(3, 60 / dailyDoseCount)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let today = Date()

        var scheduled = 0
        for dayOffset in 0..<horizonDays {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            for compound in compounds {
                guard shouldDoseToday(compound: compound, day: day, cal: cal) else { continue }
                for timeStr in compound.doseTimes {
                    guard scheduled < 60 else { return }
                    guard let fireDate = parseTime(timeStr, on: day, cal: cal) else { continue }
                    guard fireDate > Date() else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = "\(compound.compoundName) dose due"
                    content.body = "\(Int(compound.doseMcg)) mcg — tap to log"
                    content.sound = .default
                    content.categoryIdentifier = doseReminderCategory
                    content.userInfo = [
                        "compound_name": compound.compoundName,
                        "dose_mcg": compound.doseMcg,
                        "protocol_id": compound.protocolId.uuidString
                    ]

                    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    let id = "dose_\(compound.id.uuidString)_\(dayOffset)_\(timeStr)"
                    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                    try? await center.add(request)
                    scheduled += 1
                }
            }
        }
    }

    private static func shouldDoseToday(compound: LocalProtocolCompound, day: Date, cal: Calendar) -> Bool {
        let weekday = cal.component(.weekday, from: day)  // 1=Sun..7=Sat
        let isoWeekday = weekday == 1 ? 7 : weekday - 1  // 1=Mon..7=Sun

        switch compound.frequency {
        case "daily":      return true
        case "eod":
            let dayNum = cal.ordinality(of: .day, in: .era, for: day) ?? 0
            return dayNum % 2 == 0
        case "3x_weekly":  return [1, 3, 5].contains(isoWeekday)
        case "2x_weekly":  return [1, 4].contains(isoWeekday)
        case "weekly":     return isoWeekday == 1
        case "5on_2off":   return ![6, 7].contains(isoWeekday)
        case "mwf":        return [1, 3, 5].contains(isoWeekday)
        case "custom":     return compound.customDays.contains(isoWeekday)
        default:           return true
        }
    }

    private static func parseTime(_ timeStr: String, on day: Date, cal: Calendar) -> Date? {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }
}
