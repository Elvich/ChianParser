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

from sqlalchemy import text, inspect
# Фабрика асинхронных сессий
async_session_maker = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False
)

def migrate_db(connection) -> None:
    """
    Выполняет миграцию для добавления новых колонок в таблицу apartment,
    если они отсутствуют. Поддерживает PostgreSQL и SQLite.
    """
    inspector = inspect(connection)
    
    # Проверяем, существует ли таблица apartment
    if not inspector.has_table("apartment"):
        return
        
    columns = [col['name'] for col in inspector.get_columns('apartment')]
    
    # Новые колонки и их типы в SQL
    # Использование JSONB для PostgreSQL, JSON для SQLite
    is_postgres = connection.dialect.name == "postgresql"
    json_type = "JSONB" if is_postgres else "JSON"
    
    new_cols = [
        ('title', 'VARCHAR'),
        ('url', 'VARCHAR'),
        ('living_space', 'FLOAT'),
        ('kitchen_space', 'FLOAT'),
        ('house_material', 'VARCHAR'),
        ('year_built', 'INTEGER'),
        ('ceiling_height', 'FLOAT'),
        ('bathroom_type', 'VARCHAR'),
        ('balcony', 'VARCHAR'),
        ('window_view', 'VARCHAR'),
        ('repair', 'VARCHAR'),
        ('furniture', 'BOOLEAN'),
        ('metro_name', 'VARCHAR'),
        ('metro_distance_minutes', 'INTEGER'),
        ('metro_transport_type', 'VARCHAR'),
        ('parking', 'VARCHAR'),
        ('elevator', 'VARCHAR'),
        ('image_urls', json_type),
        ('semantic_tags', json_type),
        ('seller_type', 'VARCHAR'),
        ('seller_name', 'VARCHAR'),
        ('views_today', 'INTEGER'),
        ('views_total', 'INTEGER'),
        ('published_date', 'TIMESTAMP'),
        ('previous_views_total', 'INTEGER'),
        ('previous_views_date', 'TIMESTAMP'),
        ('is_detailed_parsed', 'BOOLEAN DEFAULT FALSE'),
        ('is_auction', 'BOOLEAN DEFAULT FALSE'),
        ('is_deposit_paid', 'BOOLEAN DEFAULT FALSE'),
        ('is_alternative', 'BOOLEAN DEFAULT FALSE'),
        ('is_share', 'BOOLEAN DEFAULT FALSE'),
        ('is_paid_promotion', 'BOOLEAN DEFAULT FALSE'),
        ('promotion_type', 'VARCHAR'),
        ('okrug', 'VARCHAR'),
        ('district', 'VARCHAR'),
    ]
    
    for col_name, col_type in new_cols:
        if col_name not in columns:
            try:
                # В PostgreSQL/SQLite ALTER TABLE ADD COLUMN работает одинаково
                connection.execute(text(f"ALTER TABLE apartment ADD COLUMN {col_name} {col_type}"))
                print(f"✅ Успешно добавлена колонка {col_name} в таблицу apartment.")
            except Exception as e:
                print(f"⚠️ Ошибка при добавлении колонки {col_name}: {e}")

async def init_db() -> None:
    """
    Инициализирует таблицы в базе данных.
    Вызывается при старте приложения.
    """
    async with engine.begin() as conn:
        # Для PostgreSQL/SQLite создаем таблицы, если они еще не существуют
        await conn.run_sync(SQLModel.metadata.create_all)
        # Выполняем миграцию существующих таблиц
        await conn.run_sync(migrate_db)

async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """
    Зависимость (Dependency Injection) для получения сессии базы данных в FastAPI.
    """
    async with async_session_maker() as session:
        yield session

