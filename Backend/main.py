import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI

from api.routes import appcast, health, updates, apartments, scoring, analytics, recommendations
from core.db import init_db
from core.scheduler import start_scheduler, shutdown_scheduler

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("chianparser.main")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # При старте приложения инициализируем базу данных и запускаем планировщик
    logger.info("Инициализация базы данных и планировщика задач при старте...")
    await init_db()
    start_scheduler()
    yield
    # При остановке приложения останавливаем планировщик
    shutdown_scheduler()

app = FastAPI(
    title="ChianParser Backend",
    version="0.1.0",
    lifespan=lifespan
)

# Подключение роутеров к приложению с префиксами
app.include_router(health.router, prefix="/api/v1")
app.include_router(updates.router, prefix="/api/v1")
app.include_router(appcast.router, prefix="/api/v1")
app.include_router(apartments.router, prefix="/api/v1")
app.include_router(scoring.router, prefix="/api/v1")
app.include_router(analytics.router, prefix="/api/v1")
app.include_router(recommendations.router, prefix="/api/v1")
