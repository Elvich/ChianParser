from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional

router = APIRouter(tags=["updates"])


class AppUpdate(BaseModel):
    version: str
    download_url: str
    release_notes: str
    is_critical: bool = False


@router.get("/updates/latest", response_model=Optional[AppUpdate])
async def get_latest_update(current_version: str) -> Optional[AppUpdate]:
    # TODO: implement version comparison and return latest update from DB
    return None
