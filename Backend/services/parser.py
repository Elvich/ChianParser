import asyncio
import logging
from datetime import datetime
from urllib.parse import urlparse
import httpx
from playwright.async_api import async_playwright
from playwright_stealth import Stealth
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from core.config import settings
from core.db import async_session_maker
from core.scoring import recalculate_scores
from models.database import Apartment, ScoringConfiguration

# Настройка логирования
logger = logging.getLogger("chianparser.parser")
logger.setLevel(logging.INFO)

async def send_telegram_alert(message: str) -> None:
    """
    Отправляет уведомление об ошибке в Telegram.
    """
    if not settings.TELEGRAM_BOT_TOKEN or not settings.TELEGRAM_CHAT_ID:
        logger.warning(f"⚠️ Telegram оповещения не настроены. Сообщение: {message}")
        return
        
    url = f"https://api.telegram.org/bot{settings.TELEGRAM_BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": settings.TELEGRAM_CHAT_ID,
        "text": f"🚨 <b>[ChianParser Бэкенд]</b>\n{message}",
        "parse_mode": "HTML"
    }
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(url, json=payload, timeout=10.0)
            if response.status_code != 200:
                logger.error(f"Ошибка отправки Telegram-алерта: {response.text}")
    except Exception as e:
        logger.error(f"Исключение при отправке Telegram-алерта: {e}")


async def run_stealth_parser() -> None:
    """
    Фоновая задача стелс-парсинга объявлений с Циан.
    Запускается по расписанию через APScheduler.
    """
    logger.info("🚀 Запуск фонового парсинга квартир...")
    
    async with async_session_maker() as session:
        config_statement = select(ScoringConfiguration).where(ScoringConfiguration.is_active == True)
        config_result = await session.exec(config_statement)
        config = config_result.first()
        if not config:
            config = ScoringConfiguration()
            session.add(config)
            await session.commit()
            await session.refresh(config)
            
    proxy_config = None
    if settings.PROXY_URL:
        try:
            parsed = urlparse(settings.PROXY_URL)
            proxy_config = {
                "server": f"{parsed.scheme}://{parsed.hostname}:{parsed.port}"
            }
            if parsed.username:
                proxy_config["username"] = parsed.username
            if parsed.password:
                proxy_config["password"] = parsed.password
            logger.info(f"Используется мобильный прокси: {parsed.hostname}")
        except Exception as e:
            err_msg = f"Ошибка разбора PROXY_URL '{settings.PROXY_URL}': {e}"
            logger.error(err_msg)
            await send_telegram_alert(err_msg)
            
    browser = None
    playwright_inst = None
    
    try:
        playwright_inst = await async_playwright().start()
        
        try:
            browser = await playwright_inst.chromium.launch(
                headless=True,
                proxy=proxy_config
            )
        except Exception as e:
            if "Executable doesn't exist" in str(e):
                err_msg = (
                    "Chromium не установлен для Playwright.\n"
                    "Пожалуйста, запустите в терминале: <code>playwright install chromium</code>"
                )
                logger.error(err_msg)
                await send_telegram_alert(err_msg)
                return
            raise e
            
        context = await browser.new_context(
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            viewport={"width": 1280, "height": 800}
        )
        
        page = await context.new_page()
        
        stealth = Stealth()
        await stealth.apply_stealth_async(page)
        
        target_url = "https://www.cian.ru/snyat-kvartiru/"
        logger.info(f"Переход на страницу: {target_url}")
        
        await page.goto(target_url, wait_until="networkidle", timeout=30000)
        
        demo_apts_data = [
            {
                "cian_id": "301294821",
                "rooms": 1,
                "space": 38.5,
                "price": 45000.0,
                "floor": 4,
                "max_floor": 12,
                "address": "Москва, ул. Ленина, д. 10",
                "is_studio": False,
                "is_apartment": False,
                "features": {"metro_distance_minutes": 7, "renovation": "euro"}
            },
            {
                "cian_id": "301294822",
                "rooms": 2,
                "space": 54.0,
                "price": 65000.0,
                "floor": 1,
                "max_floor": 9,
                "address": "Москва, пр. Мира, д. 25",
                "is_studio": False,
                "is_apartment": False,
                "features": {"metro_distance_minutes": 3, "renovation": "cosmetic"}
            },
            {
                "cian_id": "301294823",
                "rooms": 1,
                "space": 22.0,
                "is_studio": True,
                "price": 35000.0,
                "floor": 5,
                "max_floor": 16,
                "address": "Москва, ул. Новая, д. 5",
                "is_apartment": False,
                "features": {"metro_distance_minutes": 18, "renovation": "none"}
            },
            {
                "cian_id": "301294824",
                "rooms": 3,
                "space": 78.0,
                "price": 110000.0,
                "floor": 14,
                "max_floor": 14,
                "address": "Москва, ул. Тверская, д. 1",
                "is_studio": False,
                "is_apartment": True,
                "features": {"metro_distance_minutes": 1, "renovation": "designer"}
            },
            {
                "cian_id": "301294825",
                "rooms": 2,
                "space": 42.0,
                "price": 52000.0,
                "floor": 8,
                "max_floor": 17,
                "address": "Москва, ул. Гагарина, д. 12",
                "is_studio": False,
                "is_apartment": False,
                "features": {"metro_distance_minutes": 12, "renovation": "euro"}
            }
        ]
        
        parsed_count = 0
        skipped_count = 0
        
        async with async_session_maker() as session:
            for data in demo_apts_data:
                if config.excludeStudios and data["is_studio"]:
                    logger.info(f"Skipping studio: cian_id={data['cian_id']}")
                    skipped_count += 1
                    continue
                    
                if config.excludeApartments and data["is_apartment"]:
                    logger.info(f"Skipping apartment type: cian_id={data['cian_id']}")
                    skipped_count += 1
                    continue
                    
                stmt = select(Apartment).where(Apartment.cian_id == data["cian_id"])
                res = await session.exec(stmt)
                apt = res.first()
                
                price_sqm = data["price"] / data["space"]
                
                if not apt:
                    apt = Apartment(
                        cian_id=data["cian_id"],
                        rooms=data["rooms"],
                        space=data["space"],
                        price=data["price"],
                        price_sqm=price_sqm,
                        floor=data["floor"],
                        max_floor=data["max_floor"],
                        address=data["address"],
                        is_studio=data["is_studio"],
                        is_apartment=data["is_apartment"],
                        features=data["features"],
                        created_at=datetime.utcnow(),
                        updated_at=datetime.utcnow()
                    )
                else:
                    apt.price = data["price"]
                    apt.price_sqm = price_sqm
                    apt.floor = data["floor"]
                    apt.max_floor = data["max_floor"]
                    apt.address = data["address"]
                    apt.features = data["features"]
                    apt.updated_at = datetime.utcnow()
                    
                session.add(apt)
                parsed_count += 1
                
            await session.commit()
            
            all_stmt = select(Apartment)
            all_res = await session.exec(all_stmt)
            all_apts = all_res.all()
            
            if all_apts:
                updated_apts = recalculate_scores(list(all_apts), config)
                for u_apt in updated_apts:
                    session.add(u_apt)
                await session.commit()
                
        logger.info(f"Парсинг успешно завершен. Успешно обработано: {parsed_count}, отфильтровано: {skipped_count}")
        
    except Exception as e:
        err_msg = f"Критическая ошибка во время выполнения парсера: {e}"
        logger.exception(err_msg)
        await send_telegram_alert(err_msg)
        
    finally:
        if browser:
            await browser.close()
        if playwright_inst:
            await playwright_inst.stop()
