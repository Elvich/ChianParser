//
//  SettingsView.swift
//  ChianParser
//
//  Configurable demand thresholds for FlipScore analysis.
//

import SwiftUI

struct SettingsView: View {
    // Demand thresholds stored persistently
    @AppStorage("demandThresholdModerate") private var moderate: Int = DemandThresholds.default.moderate
    @AppStorage("demandThresholdMarket")   private var market: Int   = DemandThresholds.default.market
    @AppStorage("demandThresholdHot")      private var hot: Int      = DemandThresholds.default.hot

    var body: some View {
        Form {
            Section {
                thresholdStepper(label: "Умеренный спрос от", value: $moderate, range: 10...500)
                thresholdStepper(label: "Рыночный спрос от",  value: $market,   range: 10...500)
                thresholdStepper(label: "Горячий спрос от",   value: $hot,      range: 10...1000)
            } header: {
                Label("Пороги спроса (просмотров/день)", systemImage: "slider.horizontal.3")
            } footer: {
                Text("Эти значения используются для классификации уровня интереса к объявлению по количеству просмотров в день.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                demandPreviewRow(.low,      threshold: nil)
                demandPreviewRow(.moderate, threshold: moderate)
                demandPreviewRow(.market,   threshold: market)
                demandPreviewRow(.hot,      threshold: hot)
            } header: {
                Label("Предпросмотр уровней", systemImage: "eye")
            }

            Section {
                Button("Сбросить по умолчанию") {
                    moderate = DemandThresholds.default.moderate
                    market   = DemandThresholds.default.market
                    hot      = DemandThresholds.default.hot
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Настройки анализа")
    }

    // MARK: - Helpers

    private func thresholdStepper(label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range, step: 10) {
            HStack {
                Text(label)
                Spacer()
                Text("≥ \(value.wrappedValue)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func demandPreviewRow(_ level: DemandLevel, threshold: Int?) -> some View {
        HStack {
            Image(systemName: level.icon)
                .foregroundStyle(level.color)
                .frame(width: 20)
            Text(level.label)

            Spacer()

            if let threshold {
                Text("≥ \(threshold) просм./день")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("< \(moderate) просм./день")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .frame(width: 400, height: 500)
}
