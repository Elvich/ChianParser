from fastapi import APIRouter, Depends, status
from sqlmodel.ext.asyncio.session import AsyncSession

from core.db import get_session
from core.security import verify_api_key
from models.database import UserEvent
from models.schemas import UserEventCreate

router = APIRouter(prefix="/analytics", tags=["analytics"])

@router.post("/events", response_model=UserEvent, status_code=status.HTTP_201_CREATED)
async def create_analytics_event(
    payload: UserEventCreate,
    session: AsyncSession = Depends(get_session),
    _api_key: str = Depends(verify_api_key)
) -> UserEvent:
    """
    Записывает новое событие аналитики (просмотр, лайк, дизлайк квартиры) в базу данных.
    """
    db_event = UserEvent(
        event_type=payload.event_type,
        apartment_id=payload.apartment_id,
        payload=payload.payload or {}
    )
    
    session.add(db_event)
    await session.commit()
    await session.refresh(db_event)
    
    return db_event
