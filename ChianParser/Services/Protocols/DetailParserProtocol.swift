//
//  DetailParserProtocol.swift
//  ChianParser
//

import Foundation

/// Abstracts the parsing of a single apartment's detail page (JSON or HTML fallback).
protocol DetailParserProtocol {
    func parseJSON(jsonString: String, apartment: Apartment)
    func parseHTML(html: String, apartment: Apartment)
}
