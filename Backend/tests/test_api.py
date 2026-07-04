import pytest
from httpx import AsyncClient
from core.config import settings


@pytest.mark.asyncio
async def test_health_check(client: AsyncClient):
    response = await client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.asyncio
async def test_api_key_protection(client: AsyncClient):
    # Без X-API-Key
    response = await client.get("/api/v1/apartments/delta")
    assert response.status_code == 401

    # С неверным API ключом
    response = await client.get(
        "/api/v1/apartments/delta", headers={"X-API-Key": "wrong_key"}
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_scoring_config_and_delta(client: AsyncClient):
    headers = {"X-API-Key": settings.API_KEY}

    # Обновляем конфигурацию скоринга
    config_data = {
        "name": "Новая конфигурация",
        "priceScoreWeight": 40,
        "metroProximityWeight": 25,
        "locationFloorWeight": 20,
        "areaScoreWeight": 15,
    }
    response = await client.put(
        "/api/v1/scoring/config", json=config_data, headers=headers
    )
    assert response.status_code == 200
    assert response.json()["name"] == "Новая конфигурация"
    assert response.json()["metroProximityWeight"] == 25

    # Проверяем получение дельты
    response = await client.get("/api/v1/apartments/delta", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert "apartments" in data
    assert "server_time" in data
    assert len(data["apartments"]) == 0
