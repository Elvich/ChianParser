from datetime import datetime
from typing import Optional, Dict, Any
from sqlmodel import SQLModel, Field, Column, JSON

class Apartment(SQLModel, table=True):
    """
    Модель квартиры для базы данных.
    Хранит информацию о спарсенных объектах недвижимости.
    """
    id: Optional[int] = Field(default=None, primary_key=True)
    
    # Уникальный идентификатор объявления на Циан
    cian_id: str = Field(unique=True, index=True, nullable=False)
    
    # Основные характеристики
    rooms: int = Field(nullable=False)
    space: float = Field(nullable=False)
    price: float = Field(nullable=False)
    price_sqm: float = Field(nullable=False, index=True) # Цена за кв. м
    floor: int = Field(nullable=False)
    max_floor: int = Field(nullable=False)
    address: str = Field(nullable=False)
    
    # Гео-координаты
    latitude: Optional[float] = Field(default=None, nullable=True)
    longitude: Optional[float] = Field(default=None, nullable=True)
    
    # Дополнительная информация
    description: Optional[str] = Field(default=None, nullable=True)
    image_url: Optional[str] = Field(default=None, nullable=True)
    
    # Флаги исключений
    is_studio: bool = Field(default=False, nullable=False)
    is_apartment: bool = Field(default=False, nullable=False)
    
    # Оценка (скоринг) объекта
    scoring_value: Optional[float] = Field(default=None, nullable=True, index=True)
    
    # Дополнительные свойства (например, расстояние до метро, ремонт, тип здания)
    features: dict = Field(default_factory=dict, sa_column=Column(JSON))
    
    # Временные метки
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class ScoringConfiguration(SQLModel, table=True):
    """
    Модель конфигурации весов и параметров скоринга.
    Настройки управляются пользователем из macOS приложения.
    """
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(default="Default Config", nullable=False)
    is_active: bool = Field(default=True, nullable=False)
    
    # Флаги подсистем скоринга
    isCustomAreaScoreEnabled: bool = Field(default=True, nullable=False)
    isPercentileBenchmarkEnabled: bool = Field(default=True, nullable=False)
    
    # Правила фильтрации
    excludeStudios: bool = Field(default=True, nullable=False)
    excludeApartments: bool = Field(default=True, nullable=False)
    
    # Параметры бенчмаркинга
    targetPercentile: float = Field(default=0.80, nullable=False)
    
    # Веса для формулы скоринга (в сумме должны давать 100)
    priceScoreWeight: int = Field(default=40, nullable=False)
    metroProximityWeight: int = Field(default=25, nullable=False)
    locationFloorWeight: int = Field(default=20, nullable=False)
    areaScoreWeight: int = Field(default=15, nullable=False)
    
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class UserEvent(SQLModel, table=True):
    """
    Модель для аналитики пользовательских действий.
    Собирает события просмотров, лайков и дизлайков.
    """
    id: Optional[int] = Field(default=None, primary_key=True)
    event_type: str = Field(index=True, nullable=False) # view, like, dislike
    
    # Связь с квартирой
    apartment_id: Optional[int] = Field(default=None, foreign_key="apartment.id", nullable=True)
    
    # Дополнительные данные события в формате JSON
    payload: dict = Field(default_factory=dict, sa_column=Column(JSON))
    
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
