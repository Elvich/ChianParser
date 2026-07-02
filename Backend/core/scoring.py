from typing import List
from models.database import Apartment, ScoringConfiguration

def calculate_percentile(values: List[float], percentile: float) -> float:
    """
    Вычисляет значение перцентиля для списка чисел (линейная интерполяция).
    """
    if not values:
        return 0.0
    sorted_val = sorted(values)
    k = (len(sorted_val) - 1) * percentile
    f = int(k)
    c = f + 1
    if c < len(sorted_val):
        return sorted_val[f] + (sorted_val[c] - sorted_val[f]) * (k - f)
    else:
        return sorted_val[f]

def calculate_area_score(space: float, config: ScoringConfiguration) -> float:
    """
    Рассчитывает оценку площади (от 0 до 100) на основе матрицы ликвидности.
    """
    if config.isCustomAreaScoreEnabled:
        # Оптимизированная под ликвидность кривая (Bell Curve)
        if 35.0 <= space <= 50.0:
            return 100.0  # Идеально для флиппинга (1-2 комнатные)
        elif 25.0 <= space < 35.0:
            return 73.3   # Микро-юниты с высокой ликвидностью
        elif 50.0 < space <= 70.0:
            return 40.0   # Средняя ликвидность (семейные квартиры)
        else:
            return 13.3   # Низкая ликвидность (<25м² или >70м²)
    else:
        # Legacy линейный расчет
        if space >= 60.0:
            return 100.0
        elif space >= 45.0:
            return 73.3
        elif space >= 30.0:
            return 40.0
        else:
            return 13.3

def calculate_floor_score(floor: int, max_floor: int) -> float:
    """
    Рассчитывает оценку этажности (от 0 до 100).
    Дисконтирует первый и последний этажи.
    """
    if floor == 1:
        return 20.0  # Первый этаж - наименее ликвидный
    if floor == max_floor and max_floor > 1:
        return 50.0  # Последний этаж - средний риск/ликвидность
    return 100.0     # Средние этажи - максимальная оценка

def calculate_metro_score(features: dict) -> float:
    """
    Рассчитывает оценку близости к метро на основе минут пешком/транспортом.
    """
    # Ищем ключи, связанные с расстоянием до метро
    metro_min = features.get("metro_distance_minutes") or features.get("metro_min")
    if metro_min is None:
        return 50.0  # Средний балл при отсутствии данных
        
    try:
        minutes = float(metro_min)
    except (ValueError, TypeError):
        return 50.0
        
    if minutes <= 5:
        return 100.0
    elif minutes <= 10:
        return 80.0
    elif minutes <= 15:
        return 50.0
    elif minutes <= 20:
        return 20.0
    else:
        return 0.0

def recalculate_scores(apartments: List[Apartment], config: ScoringConfiguration) -> List[Apartment]:
    """
    Пересчитывает scoring_value для списка квартир на основе конфигурации.
    """
    if not apartments:
        return []
        
    # Вычисляем бенчмарк цены за кв. метр по рынку
    prices_sqm = [apt.price_sqm for apt in apartments]
    
    # Задаем целевой перцентиль
    target_pct = config.targetPercentile if config.isPercentileBenchmarkEnabled else 0.50
    exit_price_sqm = calculate_percentile(prices_sqm, target_pct)
    
    if exit_price_sqm <= 0:
        exit_price_sqm = 1.0 # Защита от деления на ноль
        
    for apt in apartments:
        # 1. Оценка цены (Price Score). Сравниваем цену за кв. м с целевой (exit_price_sqm)
        # Если наша цена за кв. м ниже целевой, то есть потенциал прибыли (арбитраж)
        price_diff_pct = (exit_price_sqm - apt.price_sqm) / exit_price_sqm
        # Дисконт в 50% дает 100 баллов, отсутствие дисконта или наценка - 0 баллов
        price_score = max(0.0, min(100.0, price_diff_pct * 200.0))
        
        # 2. Оценка площади (Area Score)
        area_score = calculate_area_score(apt.space, config)
        
        # 3. Оценка этажа (Floor Score)
        floor_score = calculate_floor_score(apt.floor, apt.max_floor)
        
        # 4. Оценка метро (Metro Score)
        metro_score = calculate_metro_score(apt.features or {})
        
        # Интегральный показатель скоринга с учетом весов
        total_score = (
            price_score * config.priceScoreWeight +
            area_score * config.areaScoreWeight +
            floor_score * config.locationFloorWeight +
            metro_score * config.metroProximityWeight
        ) / 100.0
        
        apt.scoring_value = round(total_score, 2)
        
    return apartments
