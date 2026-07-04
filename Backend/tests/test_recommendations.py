import pytest
from models.database import Apartment
from core.recommendations import (
    apartment_to_vector,
    cosine_similarity,
    get_recommendations,
)


def test_cosine_similarity():
    v1 = [1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    v2 = [1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    assert cosine_similarity(v1, v2) == pytest.approx(1.0)

    v3 = [0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    assert cosine_similarity(v1, v3) == pytest.approx(0.0)


def test_apartment_to_vector():
    apt = Apartment(
        id=1,
        cian_id="123",
        rooms=1,
        space=30.0,
        price=30000.0,
        price_sqm=1000.0,
        floor=1,
        max_floor=5,
        address="Тестовый адрес",
        features={"metro_distance_minutes": 5},
    )
    vec = apartment_to_vector(apt)
    assert len(vec) == 12
    # 1 комната -> vec[0] == 1.0
    assert vec[0] == 1.0
    # площадь < 35 -> vec[3] == 1.0
    assert vec[3] == 1.0
    # метро <= 5 -> vec[7] == 1.0
    assert vec[7] == 1.0
    # первый этаж -> vec[10] == 1.0
    assert vec[10] == 1.0


def test_recommendations_without_history():
    apts = [
        Apartment(
            id=1,
            cian_id="1",
            rooms=1,
            space=30.0,
            price=30000.0,
            price_sqm=1000.0,
            floor=2,
            max_floor=5,
            address="A",
            scoring_value=85.0,
        ),
        Apartment(
            id=2,
            cian_id="2",
            rooms=2,
            space=45.0,
            price=50000.0,
            price_sqm=1100.0,
            floor=3,
            max_floor=5,
            address="B",
            scoring_value=95.0,
        ),
    ]
    recs = get_recommendations(user_events=[], all_apartments=apts, limit=10)
    assert len(recs) == 2
    # Без истории пользователя сортируем по scoring_value
    assert recs[0].id == 2
    assert recs[1].id == 1
