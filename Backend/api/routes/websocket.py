import logging
from datetime import datetime
from typing import Dict
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query, Depends

from core.security import verify_api_key

logger = logging.getLogger("chianparser.websocket")

router = APIRouter()


class ConnectionManager:
    """
    Менеджер соединений для WebSocket.
    Хранит активные подключения клиентов-парсеров (macOS).
    """

    def __init__(self):
        # Словарь: token -> WebSocket
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, token: str):
        await websocket.accept()
        self.active_connections[token] = websocket
        logger.info(
            f"Клиент с токеном {token} подключился. Всего узлов: {len(self.active_connections)}"
        )

    def disconnect(self, token: str):
        if token in self.active_connections:
            del self.active_connections[token]
            logger.info(
                f"Клиент с токеном {token} отключился. Осталось узлов: {len(self.active_connections)}"
            )

    async def send_task(self, token: str, task_data: dict):
        """
        Отправка задачи конкретному клиенту.
        """
        if token in self.active_connections:
            websocket = self.active_connections[token]
            await websocket.send_json(task_data)

    async def broadcast(self, message: dict):
        """
        Отправка сообщения всем подключенным клиентам.
        """
        for connection in self.active_connections.values():
            await connection.send_json(message)


manager = ConnectionManager()


@router.websocket("/ws/parsing-nodes")
async def parsing_nodes_endpoint(
    websocket: WebSocket, token: str = Query(..., description="Токен авторизации узла")
):
    """
    WebSocket эндпоинт для подключения клиентов-парсеров (macOS).
    Проверяет токен (здесь простая заглушка) и держит соединение в пуле.
    """
    # TODO: Проверка токена по базе данных (таблица User)
    if not token or token == "invalid":
        await websocket.close(code=1008, reason="Неверный токен")
        return

    await manager.connect(websocket, token)

    try:
        while True:
            # Ожидаем сообщения от клиента (результаты парсинга или пинг)
            data = await websocket.receive_json()
            logger.info(f"Получены данные от {token}: {data}")

            # TODO: Обработка результатов парсинга

            # Пример ответа
            await websocket.send_json(
                {"status": "received", "action": data.get("action")}
            )

    except WebSocketDisconnect:
        manager.disconnect(token)


@router.post("/ws/test-task", tags=["websocket"])
async def send_test_task(_api_key: str = Depends(verify_api_key)):
    """
    Отладочный эндпоинт для отправки тестовой задачи всем подключенным узлам парсера.
    """
    test_task = {
        "action": "scrape",
        "url": "https://cian.ru/test",
        "timestamp": datetime.utcnow().isoformat(),
    }
    await manager.broadcast(test_task)
    return {
        "status": "success",
        "message": "Тестовая задача отправлена",
        "nodes_count": len(manager.active_connections),
    }
