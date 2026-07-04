from datetime import datetime, timezone
from typing import Optional, List
from fastapi import APIRouter, Depends, Query
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from core.db import get_session
from core.security import verify_api_key
from models.database import Apartment
from models.schemas import ApartmentDeltaResponse

router = APIRouter(prefix="/apartments", tags=["apartments"])

@router.get("", response_model=List[Apartment])
async def get_apartments(
    skip: int = Query(0, ge=0, description="Смещение (offset) для пагинации"),
    limit: int = Query(100, ge=1, le=1000, description="Количество возвращаемых элементов"),
    session: AsyncSession = Depends(get_session),
    _api_key: str = Depends(verify_api_key)
) -> List[Apartment]:
    """
    Получение списка квартир с пагинацией.
    """
    statement = select(Apartment).offset(skip).limit(limit)
    result = await session.exec(statement)
    return result.all()

@router.get("/delta", response_model=ApartmentDeltaResponse)
async def get_delta(
    since: Optional[datetime] = Query(
        default=None,
        description="Дата и время последней синхронизации (ISO 8601). Если не указана, возвращает все квартиры."
    ),
    session: AsyncSession = Depends(get_session),
    _api_key: str = Depends(verify_api_key)
) -> ApartmentDeltaResponse:
    """
    Дельта-синхронизация квартир.
    Возвращает список добавленных или обновленных квартир с момента 'since'.
    """
    if since is not None:
        if since.tzinfo is not None:
            since = since.astimezone(timezone.utc).replace(tzinfo=None)
        
        statement = select(Apartment).where(Apartment.updated_at > since)
    else:
        statement = select(Apartment)
        
    result = await session.exec(statement)
    apartments = result.all()
    
    return ApartmentDeltaResponse(
        apartments=apartments,
        server_time=datetime.utcnow()
    )
