//
//  SearchParserProtocol.swift
//  ChianParser
//

import Foundation

/// Abstracts the extraction of apartment listings from raw HTML/JSON content.
protocol SearchParserProtocol {
    func extractData(from html: String) -> [Apartment]
}
