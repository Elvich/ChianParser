//
//  SearchParserProtocol.swift
//  ChianParser
//

import Foundation

/// Abstracts the extraction of apartment listings from raw HTML/JSON content.
protocol SearchParserProtocol: Sendable {
    nonisolated func extractData(from html: String) -> [Apartment]
}
