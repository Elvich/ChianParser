from fastapi import FastAPI
from api.routes import appcast, health, updates

app = FastAPI(title="ChianParser Backend", version="0.1.0")

app.include_router(health.router, prefix="/api/v1")
app.include_router(updates.router, prefix="/api/v1")
app.include_router(appcast.router, prefix="/api/v1")
