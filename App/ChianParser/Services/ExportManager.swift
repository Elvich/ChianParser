//
//  ExportManager.swift
//  ChianParser
//
//  Утилита для экспорта данных в CSV и JSON
//

import Foundation
import AppKit

struct ExportManager {
    
    // MARK: - Экспорт в CSV
    
    /// Экспортирует массив квартир в CSV файл
    static func exportToCSV(apartments: [Apartment]) -> URL? {
        var csvString = "ID,Заголовок,Цена,Адрес,Площадь,Этаж,Этажей в доме,Материал,Просмотров сегодня,Просмотров всего,Дата добавления,URL\n"
        
        for apartment in apartments {
            let row = [
                apartment.id,
                escapeCSV(apartment.title),
                "\(apartment.price)",
                escapeCSV(apartment.address),
                apartment.area != nil ? "\(apartment.area!)" : "",
                apartment.floor != nil ? "\(apartment.floor!)" : "",
                apartment.totalFloors != nil ? "\(apartment.totalFloors!)" : "",
                escapeCSV(apartment.houseMaterial ?? ""),
                apartment.viewsToday != nil ? "\(apartment.viewsToday!)" : "",
                apartment.viewsTotal != nil ? "\(apartment.viewsTotal!)" : "",
                apartment.dateAdded.formatted(date: .numeric, time: .shortened),
                apartment.url
            ].joined(separator: ",")
            
            csvString += row + "\n"
        }
        
        return saveToFile(content: csvString, filename: "cian_export_\(timestamp()).csv")
    }
    
    // MARK: - Экспорт в JSON
    
    /// Экспортирует массив квартир в JSON файл
    static func exportToJSON(apartments: [Apartment]) -> URL? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let exportData = apartments.map { apartment -> [String: Any] in
            var dict: [String: Any] = [
                "id": apartment.id,
                "title": apartment.title,
                "price": apartment.price,
                "address": apartment.address,
                "url": apartment.url,
                "dateAdded": ISO8601DateFormatter().string(from: apartment.dateAdded)
            ]
            
            if let area = apartment.area { dict["area"] = area }
            if let floor = apartment.floor { dict["floor"] = floor }
            if let totalFloors = apartment.totalFloors { dict["totalFloors"] = totalFloors }
            if let material = apartment.houseMaterial { dict["houseMaterial"] = material }
            if let viewsToday = apartment.viewsToday { dict["viewsToday"] = viewsToday }
            if let viewsTotal = apartment.viewsTotal { dict["viewsTotal"] = viewsTotal }
            
            // История цен
            dict["priceHistory"] = apartment.priceHistory.map {
                [
                    "price": $0.price,
                    "date": ISO8601DateFormatter().string(from: $0.date)
                ]
            }
            
            return dict
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        return saveToFile(content: jsonString, filename: "cian_export_\(timestamp()).json")
    }
    
    // MARK: - Вспомогательные функции
    
    private static func escapeCSV(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }
    
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
    
    private static func saveToFile(content: String, filename: String) -> URL? {
        // Используем Downloads папку
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = downloadsURL.appendingPathComponent(filename)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("❌ Ошибка сохранения файла: \(error)")
            return nil
        }
    }
    
    // MARK: - Открытие файла в Finder
    
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - ExportServiceProtocol

extension ExportManager: ExportServiceProtocol {
    func exportToCSV(apartments: [Apartment]) -> URL? {
        ExportManager.exportToCSV(apartments: apartments)
    }

    func exportToJSON(apartments: [Apartment]) -> URL? {
        ExportManager.exportToJSON(apartments: apartments)
    }

    func revealInFinder(_ url: URL) {
        ExportManager.revealInFinder(url)
    }
}
