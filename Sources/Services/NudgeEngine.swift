import Foundation

struct MealWindow {
    enum WindowType { case morning, preDose, dose, postDose, evening, free }

    let type: WindowType
    let label: String
    let emoji: String
    let startTime: Date
    let endTime: Date
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let isRestricted: Bool
    let restrictionReason: String?
}

struct PartitionPlan {
    let planDate: Date
    let tdeeKcal: Int
    let goal: String
    let activeCompounds: [String]
    let windows: [MealWindow]
    let dailyProteinG: Int
    let dailyCarbsG: Int
    let dailyFatG: Int
    let nextDoseCompound: String?
    let nextDoseAt: Date?
    let preWindowStartsAt: Date?
    let restrictionWarning: String?
}

@MainActor
enum NudgeEngine {

    static func classifyWindow(
        at time: Date,
        compounds: [LocalProtocolCompound],
        rules: [CachedTimingRule],
        recentDoses: [LocalDoseLog],
        timezone: TimeZone
    ) -> String {
        let ruleMap = Dictionary(rules.map { ($0.compoundName, $0) }, uniquingKeysWith: { a, _ in a })

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let today = Date()

        // Check pre-dose windows
        for compound in compounds {
            guard let rule = ruleMap[compound.compoundName], rule.preDoseWindowMins > 0 else { continue }
            for timeStr in compound.doseTimes {
                guard let doseTime = parseTime(timeStr, on: today, cal: cal),
                      doseTime > time else { continue }
                let windowStart = doseTime.addingTimeInterval(Double(-rule.preDoseWindowMins) * 60)
                if time >= windowStart && time < doseTime {
                    return "pre_dose"
                }
            }
        }

        // Check post-dose windows
        for compound in compounds {
            guard let rule = ruleMap[compound.compoundName], rule.postDoseWindowMins > 0 else { continue }
            let relevantDoses = recentDoses.filter { $0.compoundName == compound.compoundName }
            for dose in relevantDoses {
                let windowEnd = dose.dosedAt.addingTimeInterval(Double(rule.postDoseWindowMins) * 60)
                if time > dose.dosedAt && time < windowEnd {
                    return "post_dose"
                }
            }
        }

        return "free"
    }

    static func restrictionWarning(
        at time: Date,
        compounds: [LocalProtocolCompound],
        rules: [CachedTimingRule],
        recentDoses: [LocalDoseLog],
        timezone: TimeZone
    ) -> String? {
        let ruleMap = Dictionary(rules.map { ($0.compoundName, $0) }, uniquingKeysWith: { a, _ in a })
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let today = Date()

        var warnings: [String] = []

        for compound in compounds {
            guard let rule = ruleMap[compound.compoundName] else { continue }

            // Pre-dose?
            for timeStr in compound.doseTimes {
                guard let doseTime = parseTime(timeStr, on: today, cal: cal),
                      doseTime > time else { continue }
                let windowStart = doseTime.addingTimeInterval(Double(-rule.preDoseWindowMins) * 60)
                if time >= windowStart && time < doseTime {
                    let minsLeft = Int(doseTime.timeIntervalSince(time) / 60)
                    if rule.hasCarbRestriction {
                        warnings.append("Aim for <\(rule.carbLimitG)g carbs · \(compound.compoundName) dose in \(minsLeft)m")
                    }
                }
            }

            // Post-dose?
            let relevantDoses = recentDoses.filter { $0.compoundName == compound.compoundName }
            for dose in relevantDoses {
                let windowEnd = dose.dosedAt.addingTimeInterval(Double(rule.postDoseWindowMins) * 60)
                if time > dose.dosedAt && time < windowEnd {
                    if rule.hasCarbRestriction {
                        warnings.append("Post-dose window · Aim for <\(rule.carbLimitG)g carbs · \(compound.compoundName)")
                    }
                }
            }
        }

        return warnings.isEmpty ? nil : warnings.joined(separator: " · ")
    }

    static func buildPlan(
        profile: CachedUserProfile,
        compounds: [LocalProtocolCompound],
        rules: [CachedTimingRule],
        recentDoses: [LocalDoseLog],
        for date: Date
    ) -> PartitionPlan {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: profile.timezone) ?? .current

        let ruleMap = Dictionary(rules.map { ($0.compoundName, $0) }, uniquingKeysWith: { a, _ in a })

        let totalProtein = profile.macroGoalProteinG
        let totalCarbs   = profile.macroGoalCarbsG
        let totalFat     = profile.macroGoalFatG
        let tdee         = Int(profile.tdeeKcal)

        // Build dose events for today
        struct DoseEvent {
            let compoundName: String
            let time: Date
            let preMins: Int
            let postMins: Int
            let carbLimit: Int  // -1 = no restriction
        }

        var doseEvents: [DoseEvent] = []
        for compound in compounds {
            let rule = ruleMap[compound.compoundName]
            for timeStr in compound.doseTimes {
                guard let doseTime = parseTime(timeStr, on: date, cal: cal) else { continue }
                doseEvents.append(DoseEvent(
                    compoundName: compound.compoundName,
                    time: doseTime,
                    preMins: rule?.preDoseWindowMins ?? 0,
                    postMins: rule?.postDoseWindowMins ?? 0,
                    carbLimit: rule?.hasCarbRestriction == true ? (rule?.carbLimitG ?? -1) : -1
                ))
            }
        }
        doseEvents.sort { $0.time < $1.time }

        // Find next dose
        let now = Date()
        let nextDose = doseEvents.first { $0.time > now }

        // Build windows
        var windows: [MealWindow] = []

        if doseEvents.isEmpty {
            // No protocol — one big free window
            windows.append(MealWindow(
                type: .free, label: "All Day (free)", emoji: "🕐",
                startTime: cal.startOfDay(for: date),
                endTime: cal.date(bySettingHour: 23, minute: 59, second: 0, of: date)!,
                proteinG: totalProtein, carbsG: totalCarbs, fatG: totalFat,
                isRestricted: false, restrictionReason: nil
            ))
        } else {
            // Split day around dose events
            let dayStart = cal.startOfDay(for: date)
            let dayEnd = cal.date(bySettingHour: 23, minute: 59, second: 0, of: date)!

            var cursor = dayStart
            var restrictedMins = 0

            for (i, event) in doseEvents.enumerated() {
                let preStart = event.time.addingTimeInterval(Double(-event.preMins) * 60)
                let postEnd  = event.time.addingTimeInterval(Double(event.postMins) * 60)

                // Free window before pre-dose
                if preStart > cursor {
                    let mins = Int(preStart.timeIntervalSince(cursor) / 60)
                    if mins >= 15 {
                        let emoji = i == 0 ? "🌅" : "🔄"
                        let label = i == 0 ? "Morning (free)" : "Post-dose (free)"
                        let (p, c, f) = allocateMacros(minutes: mins, inDay: 24*60, protein: totalProtein, carbs: totalCarbs, fat: totalFat)
                        windows.append(MealWindow(
                            type: i == 0 ? .morning : .postDose,
                            label: label, emoji: emoji,
                            startTime: cursor, endTime: preStart,
                            proteinG: p, carbsG: c, fatG: f,
                            isRestricted: false, restrictionReason: nil
                        ))
                    }
                }

                // Pre-dose restricted window
                if event.preMins > 0 {
                    restrictedMins += event.preMins
                    let reason = event.carbLimit >= 0 ? "\(event.compoundName): aim for <\(event.carbLimit)g carbs" : "\(event.compoundName): fasted window"
                    let (p, _, f) = allocateMacros(minutes: event.preMins, inDay: 24*60, protein: totalProtein, carbs: 0, fat: totalFat)
                    windows.append(MealWindow(
                        type: .preDose, label: "Pre-dose (restricted)", emoji: "⚡",
                        startTime: preStart, endTime: event.time,
                        proteinG: p, carbsG: event.carbLimit >= 0 ? 0 : Int(Double(totalCarbs) * Double(event.preMins) / (24*60)),
                        fatG: f,
                        isRestricted: true, restrictionReason: reason
                    ))
                }

                // Dose marker
                windows.append(MealWindow(
                    type: .dose, label: "\(event.compoundName) dose", emoji: "💉",
                    startTime: event.time, endTime: event.time,
                    proteinG: 0, carbsG: 0, fatG: 0,
                    isRestricted: false, restrictionReason: nil
                ))

                // Post-dose restricted window
                if event.postMins > 0 {
                    restrictedMins += event.postMins
                    let reason = event.carbLimit >= 0 ? "\(event.compoundName): aim for <\(event.carbLimit)g carbs post-dose" : nil
                    let (p, _, f) = allocateMacros(minutes: event.postMins, inDay: 24*60, protein: totalProtein, carbs: 0, fat: totalFat)
                    windows.append(MealWindow(
                        type: .postDose, label: "Post-dose (restricted)", emoji: "⚡",
                        startTime: event.time, endTime: postEnd,
                        proteinG: p, carbsG: 0, fatG: f,
                        isRestricted: true, restrictionReason: reason
                    ))
                }

                cursor = postEnd
            }

            // Evening free window
            if cursor < dayEnd {
                let mins = Int(dayEnd.timeIntervalSince(cursor) / 60)
                if mins >= 15 {
                    let (p, c, f) = allocateMacros(minutes: mins, inDay: 24*60, protein: totalProtein, carbs: totalCarbs, fat: totalFat)
                    windows.append(MealWindow(
                        type: .evening, label: "Evening (free)", emoji: "🌙",
                        startTime: cursor, endTime: dayEnd,
                        proteinG: p, carbsG: c, fatG: f,
                        isRestricted: false, restrictionReason: nil
                    ))
                }
            }

            let _ = restrictedMins  // used for potential warning in future
        }

        // Restriction warning for now
        let warning = restrictionWarning(
            at: now,
            compounds: compounds,
            rules: rules,
            recentDoses: recentDoses,
            timezone: TimeZone(identifier: profile.timezone) ?? .current
        )

        return PartitionPlan(
            planDate: date,
            tdeeKcal: tdee,
            goal: profile.goal,
            activeCompounds: compounds.map { $0.compoundName },
            windows: windows,
            dailyProteinG: totalProtein,
            dailyCarbsG: totalCarbs,
            dailyFatG: totalFat,
            nextDoseCompound: nextDose?.compoundName,
            nextDoseAt: nextDose?.time,
            preWindowStartsAt: nextDose.map { $0.time.addingTimeInterval(Double(-$0.preMins) * 60) },
            restrictionWarning: warning
        )
    }

    // Allocate macros proportional to window duration
    private static func allocateMacros(minutes: Int, inDay: Int, protein: Int, carbs: Int, fat: Int) -> (Int, Int, Int) {
        let ratio = Double(minutes) / Double(inDay)
        return (Int(Double(protein) * ratio), Int(Double(carbs) * ratio), Int(Double(fat) * ratio))
    }

    static func parseTime(_ timeStr: String, on day: Date, cal: Calendar) -> Date? {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }
}
