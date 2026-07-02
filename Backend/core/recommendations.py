import math
from typing import List, Dict, Any
from models.database import Apartment, UserEvent

def apartment_to_vector(apt: Apartment) -> List[float]:
    """
    Преобразует квартиру в числовой вектор признаков (размерность 12) для поиска сходства.
    Вектор описывает: комнатность, площадь, близость к метро и этажность.
    """
    vector = [0.0] * 12
    
    # 1. Комнатность (индексы 0-2)
    if apt.rooms == 1:
        vector[0] = 1.0
    elif apt.rooms == 2:
        vector[1] = 1.0
    elif apt.rooms >= 3:
        vector[2] = 1.0
        
    # 2. Площадь (индексы 3-6)
    if apt.space < 35.0:
        vector[3] = 1.0
    elif 35.0 <= apt.space <= 50.0:
        vector[4] = 1.0
    elif 50.0 < apt.space <= 70.0:
        vector[5] = 1.0
    else:
        vector[6] = 1.0
        
    # 3. Близость к метро (индексы 7-9)
    metro_min = 999.0
    features = apt.features or {}
    metro_val = features.get("metro_distance_minutes") or features.get("metro_min")
    if metro_val is not None:
        try:
            metro_min = float(metro_val)
        except (ValueError, TypeError):
            pass
            
    if metro_min <= 5.0:
        vector[7] = 1.0
    elif metro_min <= 15.0:
        vector[8] = 1.0
    else:
        vector[9] = 1.0
        
    # 4. Этажность (индексы 10-11)
    if apt.floor == 1:
        vector[10] = 1.0
    elif apt.floor == apt.max_floor and apt.max_floor > 1:
        vector[11] = 1.0
        
    return vector

def dot_product(v1: List[float], v2: List[float]) -> float:
    """Вычисляет скалярное произведение двух векторов."""
    return sum(x * y for x, y in zip(v1, v2))

def magnitude(v: List[float]) -> float:
    """Вычисляет длину (норму) вектора."""
    return math.sqrt(sum(x * x for x in v))

def cosine_similarity(v1: List[float], v2: List[float]) -> float:
    """Вычисляет косинусную близость между двумя векторами (от -1.0 до 1.0)."""
    mag1 = magnitude(v1)
    mag2 = magnitude(v2)
    if mag1 == 0.0 or mag2 == 0.0:
        return 0.0
    return dot_product(v1, v2) / (mag1 * mag2)

def build_user_preference_vector(events: List[UserEvent], apartments_map: Dict[int, Apartment]) -> List[float]:
    """
    Строит вектор предпочтений пользователя на основе его истории действий.
    Лайк дает +1.0 к вектору квартиры.
    Просмотр дает +0.2.
    Дизлайк дает -1.0.
    """
    user_vector = [0.0] * 12
    for event in events:
        apt = apartments_map.get(event.apartment_id)
        if not apt:
            continue
            
        apt_vector = apartment_to_vector(apt)
        
        # Определяем вес события
        if event.event_type == "like":
            weight = 1.0
        elif event.event_type == "view":
            weight = 0.2
        elif event.event_type == "dislike":
            weight = -1.0
        else:
            weight = 0.0
            
        for i in range(12):
            user_vector[i] += apt_vector[i] * weight
            
    return user_vector

def get_recommendations(
    user_events: List[UserEvent],
    all_apartments: List[Apartment],
    limit: int = 10
) -> List[Apartment]:
    """
    Генерирует рекомендации квартир на основе косинусного сходства.
    Если у пользователя нет истории, возвращает топ квартир по рейтингу (scoring_value).
    """
    if not all_apartments:
        return []
        
    # Карта для быстрого поиска квартир по ID
    apts_map = {apt.id: apt for apt in all_apartments if apt.id is not None}
    
    # Множества ID квартир, с которыми пользователь уже взаимодействовал (лайкал/дизлайкал)
    interacted_ids = {e.apartment_id for e in user_events if e.apartment_id is not None}
    
    # Строим вектор предпочтений пользователя
    user_vector = build_user_preference_vector(user_events, apts_map)
    user_vector_mag = magnitude(user_vector)
    
    # Если истории нет или вектор нулевой, рекомендуем лучшие квартиры по скорингу
    if not user_events or user_vector_mag == 0.0:
        # Исключаем те, с которыми были взаимодействия (если были)
        candidates = [apt for apt in all_apartments if apt.id not in interacted_ids]
        # Сортируем по scoring_value (по убыванию)
        return sorted(
            candidates,
            key=lambda x: x.scoring_value if x.scoring_value is not None else 0.0,
            reverse=True
        )[:limit]
        
    # Вычисляем косинусное сходство для квартир, которые пользователь не взаимодействовал
    recommendations_with_score = []
    for apt in all_apartments:
        if apt.id in interacted_ids:
            continue  # Не рекомендуем то, что уже оценено
            
        apt_vector = apartment_to_vector(apt)
        similarity = cosine_similarity(user_vector, apt_vector)
        recommendations_with_score.append((apt, similarity))
        
    # Сортируем кандидатов по сходству (по убыванию)
    recommendations_with_score.sort(key=lambda x: x[1], reverse=True)
    
    # Возвращаем топ-N квартир
    return [item[0] for item in recommendations_with_score[:limit]]
