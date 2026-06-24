//
//  URLBuilder.swift
//  ChianParser
//
//  Утилита для построения URL с параметрами
//

import Foundation

struct URLBuilder {
    
    /// Строит URL для конкретной страницы поиска Циан
    /// - Parameters:
    ///   - baseURL: Базовый URL (без параметра страницы)
    ///   - page: Номер страницы (начиная с 1)
    /// - Returns: URL с параметром `p=page`
    static func buildSearchURL(baseURL: String, page: Int) -> URL? {
        guard var components = URLComponents(string: baseURL) else {
            return nil
        }
        
        // Получаем существующие query items
        var queryItems = components.queryItems ?? []
        
        // Удаляем старый параметр `p` если есть
        queryItems.removeAll { $0.name == "p" }
        
        // Добавляем новый параметр страницы (только если не первая страница)
        if page > 1 {
            queryItems.append(URLQueryItem(name: "p", value: "\(page)"))
        }
        
        components.queryItems = queryItems
        
        return components.url
    }
    
    /// Извлекает базовый URL без параметра страницы
    static func extractBaseURL(from urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }
        
        // Удаляем параметр p
        components.queryItems?.removeAll { $0.name == "p" }
        
        return components.url?.absoluteString ?? urlString
    }
}
