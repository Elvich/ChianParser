from typing import List
from fastapi import APIRouter, Depends, Query
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from core.db import get_session
from core.security import verify_api_key
from core.recommendations import get_recommendations
from models.database import Apartment, UserEvent

router = APIRouter(prefix="/recommendations", tags=["recommendations"])


@router.get("", response_model=List[Apartment])
async def get_property_recommendations(
    limit: int = Query(
        default=10, ge=1, le=50, description="Максимальное количество рекомендаций"
    ),
    session: AsyncSession = Depends(get_session),
    _api_key: str = Depends(verify_api_key),
) -> List[Apartment]:
    """
    Возвращает список рекомендованных квартир на основе предпочтений пользователя (косинусное сходство).
    """
    events_statement = select(UserEvent)
    events_result = await session.exec(events_statement)
    user_events = events_result.all()

    apts_statement = select(Apartment)
    apts_result = await session.exec(apts_statement)
    all_apartments = apts_result.all()

    recommended_apts = get_recommendations(
        user_events=list(user_events), all_apartments=list(all_apartments), limit=limit
    )

    return recommended_apts
