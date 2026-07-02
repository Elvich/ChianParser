import os
from dotenv import load_dotenv
from pydantic import Field, ConfigDict
from pydantic_settings import BaseSettings

# Загружаем переменные окружения из .env файла
load_dotenv()

class Settings(BaseSettings):
    """
    Класс конфигурации приложения ChianParser Backend.
    Все настройки считываются из переменных окружения.
    """
    model_config = ConfigDict(env_file=".env", env_file_encoding="utf-8")

    # Настройки базы данных
    DATABASE_URL: str = Field(
        default="postgresql+asyncpg://postgres:postgres@localhost:5432/chianparser",
        description="URL для подключения к PostgreSQL через asyncpg"
    )
    
    # Настройки безопасности API
    API_KEY: str = Field(
        default="chian_secret_api_key_2026",
        description="API ключ для защиты эндпоинтов (X-API-Key)"
    )
    
    # Настройки парсинга
    PROXY_URL: str = Field(
        default="",
        description="URL мобильного прокси (например, http://user:pass@ip:port)"
    )
    
    # Настройки Telegram оповещений
    TELEGRAM_BOT_TOKEN: str = Field(
        default="",
        description="Токен Telegram-бота для отправки алертов"
    )
    TELEGRAM_CHAT_ID: str = Field(
        default="",
        description="ID чата Telegram для отправки алертов"
    )
    
    # Настройки S3 резервного копирования
    S3_BUCKET_NAME: str = Field(
        default="chianparser-backups",
        description="Имя бакета S3 для бэкапов"
    )
    S3_ENDPOINT_URL: str = Field(
        default="https://s3.amazonaws.com",
        description="Endpoint URL для S3"
    )
    AWS_ACCESS_KEY_ID: str = Field(
        default="",
        description="Access Key ID для S3"
    )
    AWS_SECRET_ACCESS_KEY: str = Field(
        default="",
        description="Secret Access Key для S3"
    )

# Инициализируем глобальный объект настроек
settings = Settings()
