//
//  WebSocketNodeService.swift
//  ChianParser
//

import Foundation
import OSLog
import SwiftUI

@MainActor
@Observable
final class WebSocketNodeService {
    private let logger = Logger(subsystem: "com.chianparser", category: "WebSocketNodeService")
    private var webSocketTask: URLSessionWebSocketTask?
    
    func connectIfNeeded(isEnabled: Bool) {
        if isEnabled {
            connect()
        } else {
            disconnect()
        }
    }
    
    private func connect() {
        guard webSocketTask == nil else { return }
        guard let url = URL(string: "ws://localhost:8000/ws/parsing-nodes") else { return }
        
        let request = URLRequest(url: url)
        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()
        
        logger.info("WebSocket connected to \(url)")
        receiveMessage()
    }
    
    private func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        logger.info("WebSocket disconnected")
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                self.logger.error("WebSocket error: \(error)")
                Task { @MainActor in
                    self.disconnect()
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    self.logger.info("Received task: \(text)")
                    // Здесь будет обработка задачи от сервера
                case .data(let data):
                    self.logger.info("Received data of size: \(data.count)")
                @unknown default:
                    break
                }
                
                // Продолжаем слушать
                self.receiveMessage()
            }
        }
    }
}
