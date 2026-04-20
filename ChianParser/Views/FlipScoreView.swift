//
//  FlipScoreView.swift
//  ChianParser
//
//  Displays FlipScoreResult in a structured card layout.
//

import SwiftUI

// MARK: - Full Score Card (used in ApartmentDetailView)

struct FlipScoreCard: View {
    let result: FlipScoreResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            benchmarkRow
            scoreBreakdown
            Divider()
            demandRow
        }
        .padding()
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(result.grade.color.opacity(0.15))
                    .frame(width: 56, height: 56)
                Text("\(result.totalScore)")
                    .font(.title.bold())
                    .foregroundStyle(result.grade.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: result.grade.icon)
                    Text(result.grade.label)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(result.grade.color)

                Text("FlipScore")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let discount = result.priceDiscount {
                VStack(alignment: .trailing, spacing: 2) {
                    let isBelowMarket = discount < 0  // negative = priceSqm < benchmarkSqm
                    Text(String(format: "%@%.0f%%", isBelowMarket ? "-" : "+", abs(discount * 100)))
                        .font(.title3.bold())
                        .foregroundStyle(isBelowMarket ? .green : .red)
                    Text(isBelowMarket ? "ниже рынка" : "выше рынка")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Benchmark Row

    @ViewBuilder
    private var benchmarkRow: some View {
        if let priceSqm = result.priceSqm {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Цена за м²", systemImage: "chart.bar.xaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f ₽/м²", priceSqm))
                        .font(.subheadline.bold())
                }

                if let benchSqm = result.benchmarkSqm {
                    HStack {
                        Label(
                            "Эталон\(result.benchmarkOkrug.map { " (\($0))" } ?? "")",
                            systemImage: "building.2"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f ₽/м²", benchSqm))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("(\(result.benchmarkSampleSize) кв.)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Score Breakdown

    private var scoreBreakdown: some View {
        VStack(spacing: 8) {
            ScoreRow(label: "Цена vs рынок", icon: "tag",           score: result.priceScore, max: 40)
            ScoreRow(label: "Метро",          icon: "tram",          score: result.metroScore, max: 25)
            ScoreRow(label: "Этаж",           icon: "building.2",    score: result.floorScore, max: 20)
            ScoreRow(label: "Площадь",        icon: "square.dashed", score: result.areaScore,  max: 15)
        }
    }

    // MARK: - Demand Row

    private var demandRow: some View {
        HStack(spacing: 8) {
            Image(systemName: result.demandLevel.icon)
                .foregroundStyle(result.demandLevel.color)
            Text("Спрос: \(result.demandLevel.label)")
                .font(.subheadline)

            Spacer()

            if let vpd = result.viewsPerDay {
                Text(String(format: "%.0f просм./день", vpd))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Score Row

private struct ScoreRow: View {
    let label: String
    let icon: String
    let score: Int
    let max: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .frame(width: 110, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(score) / CGFloat(max))
                }
            }
            .frame(height: 8)

            Text("\(score)/\(max)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var barColor: Color {
        let ratio = Double(score) / Double(max)
        if ratio >= 0.7 { return .green }
        if ratio >= 0.4 { return .orange }
        return .red
    }
}

// MARK: - Compact Badge (used in list rows)

struct FlipScoreBadge: View {
    let score: Int

    private var grade: FlipGrade { FlipGrade(score: score) }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: grade.icon)
                .font(.caption2)
            Text("\(score)")
                .font(.caption.bold())
        }
        .foregroundStyle(grade.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(grade.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Demand Badge

struct DemandBadge: View {
    let level: DemandLevel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: level.icon)
                .font(.caption2)
            Text(level.label)
                .font(.caption)
        }
        .foregroundStyle(level.color)
    }
}

#Preview {
    let result = FlipScoreResult(
        totalScore: 77,
        priceScore: 32,
        metroScore: 20,
        floorScore: 20,
        areaScore: 5,
        priceSqm: 220_000,
        benchmarkSqm: 280_000,
        benchmarkOkrug: "ЦАО",
        benchmarkSampleSize: 42,
        demandLevel: .market,
        viewsPerDay: 130
    )
    FlipScoreCard(result: result)
        .padding()
        .frame(width: 400)
}
