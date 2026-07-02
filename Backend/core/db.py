from typing import AsyncGenerator
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from sqlmodel import SQLModel
from sqlmodel.ext.asyncio.session import AsyncSession
from core.config import settings

# Создаем асинхронный движок базы данных
# Для SQLite в тестах используется специальный префикс, поэтому поддерживаем оба варианта
engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    future=True
)

# Фабрика асинхронных сессий
async_session_maker = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False
)

async def init_db() -> None:
    """
    Инициализирует таблицы в базе данных.
    Вызывается при старте приложения.
    """
    async with engine.begin() as conn:
        # Для PostgreSQL/SQLite создаем таблицы, если они еще не существуют
        await conn.run_sync(SQLModel.metadata.create_all)

async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """
    Зависимость (Dependency Injection) для получения сессии базы данных в FastAPI.
    """
    async with async_session_maker() as session:
        yield session
