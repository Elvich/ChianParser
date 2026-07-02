from datetime import datetime
from typing import Optional, Dict, Any, List
from pydantic import BaseModel, Field

class ScoringConfigurationUpdate(BaseModel):
    """
    Схема для обновления конфигурации скоринга.
    """
    name: Optional[str] = Field(default=None, description="Название конфигурации")
    isCustomAreaScoreEnabled: Optional[bool] = Field(default=None, description="Включить ли оптимизированный скоринг площади")
    isPercentileBenchmarkEnabled: Optional[bool] = Field(default=None, description="Включить ли перцентильный бенчмарк")
    excludeStudios: Optional[bool] = Field(default=None, description="Исключать ли студии")
    excludeApartments: Optional[bool] = Field(default=None, description="Исключать ли апартаменты (коммерческие)")
    targetPercentile: Optional[float] = Field(default=None, ge=0.50, le=0.95, description="Целевой перцентиль")
    priceScoreWeight: Optional[int] = Field(default=None, ge=0, le=100, description="Вес цены")
    metroProximityWeight: Optional[int] = Field(default=None, ge=0, le=100, description="Вес близости метро")
    locationFloorWeight: Optional[int] = Field(default=None, ge=0, le=100, description="Вес этажа")
    areaScoreWeight: Optional[int] = Field(default=None, ge=0, le=100, description="Вес площади")


class UserEventCreate(BaseModel):
    """
    Схема для записи события аналитики.
    """
    event_type: str = Field(..., description="Тип события (например: view, like, dislike)")
    apartment_id: Optional[int] = Field(default=None, description="ID квартиры в БД")
    payload: Optional[Dict[str, Any]] = Field(default_factory=dict, description="Дополнительные данные события")


class ApartmentDeltaResponse(BaseModel):
    """
    Схема для возврата дельты синхронизации.
    """
    apartments: List[Any] = Field(..., description="Список добавленных/обновленных квартир")
    server_time: datetime = Field(..., description="Текущее время сервера для последующих запросов")
