from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from core.db import get_session
from core.security import verify_api_key
from core.scoring import recalculate_scores
from models.database import ScoringConfiguration, Apartment
from models.schemas import ScoringConfigurationUpdate

router = APIRouter(prefix="/scoring", tags=["scoring"])


@router.put("/config", response_model=ScoringConfiguration)
async def update_scoring_config(
    payload: ScoringConfigurationUpdate,
    session: AsyncSession = Depends(get_session),
    _api_key: str = Depends(verify_api_key),
) -> ScoringConfiguration:
    """
    Обновляет текущую (или создает по умолчанию) конфигурацию скоринга.
    При обновлении автоматически запускает перерасчет баллов для всех квартир в базе данных.
    """
    statement = select(ScoringConfiguration).where(
        ScoringConfiguration.is_active
    )
    result = await session.exec(statement)
    config = result.first()

    if not config:
        config = ScoringConfiguration()
        session.add(config)
        await session.flush()

    update_data = payload.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(config, key, value)

    total_weight = (
        config.priceScoreWeight
        + config.metroProximityWeight
        + config.locationFloorWeight
        + config.areaScoreWeight
    )
    if total_weight != 100:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Сумма весов должна быть ровно 100. Текущая сумма: {total_weight}",
        )

    config.updated_at = datetime.utcnow()

    apt_statement = select(Apartment)
    apt_result = await session.exec(apt_statement)
    apartments = apt_result.all()

    if apartments:
        updated_apts = recalculate_scores(list(apartments), config)
        for apt in updated_apts:
            apt.updated_at = datetime.utcnow()
            session.add(apt)

    session.add(config)
    await session.commit()
    await session.refresh(config)

    return config
