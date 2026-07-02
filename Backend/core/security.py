from fastapi import Security, HTTPException, status
from fastapi.security.api_key import APIKeyHeader
from core.config import settings

# Определяем заголовок, в котором ожидается API ключ
API_KEY_HEADER = APIKeyHeader(name="X-API-Key", auto_error=False)

async def verify_api_key(api_key_header: str = Security(API_KEY_HEADER)) -> str:
    """
    Проверяет валидность переданного API ключа в заголовке X-API-Key.
    Если ключ невалидный или отсутствует, возбуждает HTTP 401.
    """
    if not api_key_header:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Отсутствует заголовок X-API-Key"
        )
    if api_key_header != settings.API_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверный API ключ"
        )
    return api_key_header
