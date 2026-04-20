import SwiftUI
import Charts

// MARK: - Weekly Macro Trend Card

struct MacroTrendCard: View {
    let logs: [LocalFoodLog]
    var targetKcal: Int? = nil
    var targetProtein: Int? = nil

    @State private var selectedMetric: MacroMetric = .calories

    enum MacroMetric: String, CaseIterable {
        case calories = "Calories"
        case protein  = "Protein"
        case carbs    = "Carbs"
        case fat      = "Fat"

        var color: Color {
            switch self {
            case .calories: return Color.appAccent
            case .protein:  return Color(hex: "1d4ed8")
            case .carbs:    return Color(hex: "b45309")
            case .fat:      return Color(hex: "9d174d")
            }
        }

        var unit: String {
            self == .calories ? "kcal" : "g"
        }
    }

    struct DayPoint: Identifiable {
        let id: String
        let date: Date
        let label: String
        let value: Double
    }

    var last7Days: [DayPoint] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset -> DayPoint in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let dayLogs = logs.filter { cal.isDate($0.loggedAt, inSameDayAs: day) }
            let value: Double
            switch selectedMetric {
            case .calories: value = Double(dayLogs.reduce(0) { $0 + $1.kcal })
            case .protein:  value = dayLogs.reduce(0) { $0 + $1.proteinG }
            case .carbs:    value = dayLogs.reduce(0) { $0 + $1.carbsG }
            case .fat:      value = dayLogs.reduce(0) { $0 + $1.fatG }
            }
            let formatter = DateFormatter()
            formatter.dateFormat = offset == 0 ? "'Today'" : "EEE"
            return DayPoint(id: day.description, date: day, label: formatter.string(from: day), value: value)
        }
    }

    var targetLine: Double? {
        switch selectedMetric {
        case .calories: return targetKcal.map { Double($0) }
        case .protein:  return targetProtein.map { Double($0) }
        default:        return nil
        }
    }

    var avgValue: Double {
        let nonZero = last7Days.filter { $0.value > 0 }
        guard !nonZero.isEmpty else { return 0 }
        return nonZero.reduce(0) { $0 + $1.value } / Double(nonZero.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("7-DAY TREND")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.appTextMeta)
                        .kerning(1.2)
                    HStack(spacing: 6) {
                        Text(avgValue > 0 ? "Avg \(formatValue(avgValue)) \(selectedMetric.unit)" : "No data yet")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(Color.appTextPrimary)
                        if let target = targetLine, avgValue > 0 {
                            let pct = Int((avgValue / target) * 100)
                            Text("\(pct)% of goal")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(pct >= 90 && pct <= 110 ? Color(hex: "16a34a") : Color(hex: "f59e0b"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((pct >= 90 && pct <= 110 ? Color(hex: "dcfce7") : Color(hex: "fef3c7")))
                                .cornerRadius(6)
                        }
                    }
                }
                Spacer()
            }

            // Metric selector pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MacroMetric.allCases, id: \.self) { metric in
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedMetric = metric } }) {
                            Text(metric.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(selectedMetric == metric ? .white : Color.appTextSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedMetric == metric ? metric.color : Color.appDivider)
                                .cornerRadius(8)
                        }
                    }
                }
            }

            // Chart
            Chart {
                ForEach(last7Days) { point in
                    BarMark(
                        x: .value("Day", point.label),
                        y: .value(selectedMetric.rawValue, point.value)
                    )
                    .foregroundStyle(barColor(for: point))
                    .cornerRadius(6)
                }

                if let target = targetLine {
                    RuleMark(y: .value("Target", target))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Color.appTextMeta)
                        .annotation(position: .trailing, alignment: .leading) {
                            Text("Goal")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color.appTextMeta)
                        }
                }
            }
            .frame(height: 140)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.appTextMeta)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.appTextMeta)
                    AxisGridLine()
                        .foregroundStyle(Color.appDivider)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private func barColor(for point: DayPoint) -> Color {
        point.value == 0 ? Color.appDivider : selectedMetric.color
    }

    private func formatValue(_ v: Double) -> String {
        String(format: "%.0f", v)
    }
}

// MARK: - Dose Compliance Chart

struct DoseComplianceCard: View {
    let compounds: [LocalProtocolCompound]
    let doseLogs: [LocalDoseLog]

    struct ComplianceDay: Identifiable {
        let id: String
        let label: String
        let date: Date
        let count: Int
        let expected: Int
    }

    var last7Days: [ComplianceDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset -> ComplianceDay in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            let count = doseLogs.filter { cal.isDate($0.dosedAt, inSameDayAs: day) }.count
            let formatter = DateFormatter()
            formatter.dateFormat = offset == 0 ? "'Today'" : "EEE"
            return ComplianceDay(
                id: day.description,
                label: formatter.string(from: day),
                date: day,
                count: count,
                expected: compounds.count
            )
        }
    }

    var avgCompliance: Int {
        let days = last7Days.filter { $0.expected > 0 }
        guard !days.isEmpty else { return 0 }
        let total = days.reduce(0.0) { $0 + min(1.0, Double($1.count) / Double($1.expected)) }
        return Int((total / Double(days.count)) * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DOSE COMPLIANCE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.appTextMeta)
                        .kerning(1.2)
                    HStack(spacing: 6) {
                        Text("\(avgCompliance)%")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(Color.appTextPrimary)
                        Text("7-day avg")
                            .font(.system(size: 12))
                            .foregroundColor(Color.appTextTertiary)
                    }
                }
                Spacer()
                Text("\(compounds.count) compound\(compounds.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.appAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.appAccentTint)
                    .cornerRadius(8)
            }

            Chart {
                ForEach(last7Days) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Doses", day.count)
                    )
                    .foregroundStyle(barColor(day).gradient)
                    .cornerRadius(6)
                }

                if compounds.count > 0 {
                    RuleMark(y: .value("Expected", compounds.count))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Color.appTextMeta)
                }
            }
            .frame(height: 120)
            .chartYScale(domain: 0...(max(compounds.count + 1, last7Days.map(\.count).max() ?? 1) + 1))
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.appTextMeta)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .stride(by: 1)) { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.appTextMeta)
                    AxisGridLine()
                        .foregroundStyle(Color.appDivider)
                }
            }
        }
        .padding(16)
        .background(Color.appCard)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private func barColor(_ day: ComplianceDay) -> Color {
        guard day.expected > 0 else { return Color.appDivider }
        if day.count == 0 { return Color.appDivider }
        let ratio = Double(day.count) / Double(day.expected)
        if ratio >= 1.0 { return Color(hex: "16a34a") }
        if ratio >= 0.5 { return Color(hex: "f59e0b") }
        return Color(hex: "dc2626")
    }
}
