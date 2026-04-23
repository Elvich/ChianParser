//
//  WaitingConditionSheet.swift
//  ChianParser
//
//  Sheet for creating or editing a WaitingCondition on an apartment.
//

import SwiftUI

struct WaitingConditionSheet: View {
    @Binding var condition: WaitingCondition
    @Environment(\.dismiss) private var dismiss

    @State private var conditionType: WaitingCondition.ConditionType
    @State private var thresholdText: String
    @State private var daysFromNow: Int
    @State private var note: String

    init(condition: Binding<WaitingCondition>) {
        _condition = condition
        _conditionType = State(initialValue: condition.wrappedValue.type)
        _thresholdText = State(initialValue: condition.wrappedValue.threshold.map { String(Int($0)) } ?? "")
        _note = State(initialValue: condition.wrappedValue.note)

        // Compute days remaining if a targetDate exists
        let days: Int
        if let target = condition.wrappedValue.targetDate {
            days = max(1, Calendar.current.dateComponents([.day], from: Date(), to: target).day ?? 7)
        } else {
            days = 7
        }
        _daysFromNow = State(initialValue: days)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Condition Type
                Section("Тип условия") {
                    Picker("Тип", selection: $conditionType) {
                        ForEach(WaitingCondition.ConditionType.allCases, id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: Parameters
                Section("Параметры") {
                    switch conditionType {
                    case .priceBelow:
                        HStack {
                            Text("Цена ниже (₽)")
                            Spacer()
                            TextField("Например 8 000 000", text: $thresholdText)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 160)
                        }
                    case .scoreAbove:
                        HStack {
                            Text("FlipScore выше")
                            Spacer()
                            TextField("Например 60", text: $thresholdText)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    case .timer:
                        Stepper("Через \(daysFromNow) дн.", value: $daysFromNow, in: 1...365)
                    }
                }

                // MARK: Note
                Section("Заметка (необязательно)") {
                    TextField("Например: жду снижения до 7.5М", text: $note)
                }
            }
            .navigationTitle("Условие ожидания")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        saveCondition()
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 340)
    }

    private var isValid: Bool {
        switch conditionType {
        case .priceBelow, .scoreAbove:
            return Double(thresholdText.replacingOccurrences(of: " ", with: "")) != nil
        case .timer:
            return daysFromNow > 0
        }
    }

    private func saveCondition() {
        var updated = WaitingCondition(type: conditionType, note: note)
        switch conditionType {
        case .priceBelow, .scoreAbove:
            updated.threshold = Double(thresholdText.replacingOccurrences(of: " ", with: ""))
        case .timer:
            updated.targetDate = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())
        }
        condition = updated
    }
}
