//
//  ChianParserUITests.swift
//  ChianParserUITests
//
//  Created by Maksim on 30.03.2026.
//

import XCTest

final class ChianParserUITests: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        // Останавливаем тесты при первом падении
        continueAfterFailure = false
        app.launch()
    }

    /// Тест 1: Проверка успешного запуска и открытия панели настроек
    @MainActor
    func testAppLaunchAndSettingsNavigation() throws {
        // Проверяем, что кнопка настроек на тулбаре присутствует
        let settingsButton = app.buttons["main.toolbar.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Кнопка настроек должна появиться на тулбаре")
        
        // Кликаем по кнопке настроек
        settingsButton.tap()
        
        // Проверяем, что открылась панель настроек (ищем кнопку таба "Скоринг")
        let scoringTab = app.buttons["Скоринг"]
        XCTAssertTrue(scoringTab.waitForExistence(timeout: 3), "Вкладка 'Скоринг' должна отображаться в окне настроек")
    }

    /// Тест 2: Проверка интерактивности во вкладке "Скоринг"
    @MainActor
    func testScoringSettingsInteractions() throws {
        // Открываем настройки
        let settingsButton = app.buttons["main.toolbar.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        
        // Переходим во вкладку "Скоринг"
        let scoringTab = app.buttons["Скоринг"]
        XCTAssertTrue(scoringTab.waitForExistence(timeout: 3))
        scoringTab.tap()
        
        // Проверяем наличие тумблеров режимов оценки
        let customAreaToggle = app.checkBoxes["settings.scoring.isCustomAreaScoreEnabled"]
        let percentileToggle = app.checkBoxes["settings.scoring.isPercentileBenchmarkEnabled"]
        
        // В macOS SwiftUI Toggle отображается как checkBoxes
        XCTAssertTrue(customAreaToggle.exists || app.switches["settings.scoring.isCustomAreaScoreEnabled"].exists)
        XCTAssertTrue(percentileToggle.exists || app.switches["settings.scoring.isPercentileBenchmarkEnabled"].exists)
        
        // Находим степперы для весов
        let priceStepper = app.steppers["settings.scoring.priceWeightStepper"]
        XCTAssertTrue(priceStepper.exists, "Степпер веса цены должен присутствовать")
    }

    /// Тест 3: Проверка открытия и закрытия панели поиска по ссылке на главном экране
    @MainActor
    func testURLSearchToggle() throws {
        // Находим кнопку поиска на тулбаре
        let searchButton = app.buttons["main.toolbar.searchButton"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        
        // Кликаем для показа поля поиска
        searchButton.tap()
        
        // Проверяем, что текстовое поле поиска появилось
        // Текстовое поле поиска имеет плейсхолдер или привязано к URLSearchBar
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3), "Поле ввода ссылки должно появиться")
        
        // Скрываем панель поиска обратным кликом
        searchButton.tap()
    }
}
