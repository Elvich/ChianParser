import asyncio
import logging
import re
from datetime import datetime
from urllib.parse import urlparse

import httpx
from playwright.async_api import async_playwright
from playwright_stealth import Stealth
from sqlmodel import select

from core.config import settings
from core.db import async_session_maker
from core.scoring import recalculate_scores
from models.database import Apartment, ScoringConfiguration

# Настройка логирования
logger = logging.getLogger("chianparser.parser")
logger.setLevel(logging.INFO)


async def send_telegram_alert(message: str) -> None:
    """
    Отправляет уведомление об ошибке или событии в Telegram.
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


# ---------------------------------------------------------------------------
# Вспомогательные функции парсинга
# ---------------------------------------------------------------------------

def _parse_room_info(text: str) -> dict:
    """
    Разбирает строку вида «4-комн. квартира, 177 м², 10/10 этаж».
    Возвращает словарь с rooms, space, floor, max_floor, is_studio, is_apartment.
    """
    result = {
        "rooms": 1,
        "space": 0.0,
        "floor": 1,
        "max_floor": 1,
        "is_studio": False,
        "is_apartment": False,
    }

    low = text.lower()

    # Студия
    if "студия" in low or "studio" in low:
        result["is_studio"] = True
        result["rooms"] = 1
    else:
        m = re.search(r"(\d+)-комн", low)
        if m:
            result["rooms"] = int(m.group(1))

    # Апартаменты
    if "апартамент" in low:
        result["is_apartment"] = True

    # Площадь: «177 м²» или «177,5 м²»
    m = re.search(r"([\d]+[,\.]?[\d]*)\s*м²", text)
    if m:
        result["space"] = float(m.group(1).replace(",", "."))

    # Этаж: «10/10 этаж»
    m = re.search(r"(\d+)/(\d+)\s*этаж", text)
    if m:
        result["floor"] = int(m.group(1))
        result["max_floor"] = int(m.group(2))

    return result


def _parse_price(text: str) -> float:
    """
    Разбирает строку вида «600 000 ₽/мес.» → 600000.0.
    Поддерживает обычные, неразрывные и тонкие пробелы.
    """
    m = re.search(r"([\d\s\xa0\u202f]+)\s*₽", text)
    if m:
        digits = re.sub(r"[\s\xa0\u202f]", "", m.group(1))
        if digits:
            return float(digits)
    return 0.0


def _parse_metro_distance(text: str) -> int:
    """
    Разбирает строку вида «14 минут пешком» → 14.
    """
    m = re.search(r"(\d+)\s*мин", text)
    if m:
        return int(m.group(1))
    return 0


async def _extract_card_data(card) -> dict | None:
    """
    Извлекает все поля из одной карточки объявления (article[data-name="CardComponent"]).
    Возвращает словарь с данными или None, если карточку не удалось разобрать.
    """
    try:
        # cian_id из href первой ссылки
        href = await card.locator("a").first.get_attribute("href") or ""
        m = re.search(r"/flat/(\d+)/", href)
        if not m:
            logger.debug(f"Не удалось извлечь cian_id из href: {href[:80]}")
            return None
        cian_id = m.group(1)

        # Комнаты / площадь / этаж
        room_info: dict = {
            "rooms": 1, "space": 0.0, "floor": 1, "max_floor": 1,
            "is_studio": False, "is_apartment": False
        }
        try:
            title_el = card.locator('[data-name="GeneralInfoSectionRowComponent"]').first
            title_text = await title_el.inner_text()
            room_info = _parse_room_info(title_text)
        except Exception:
            pass

        # Цена из элемента с классом, содержащим "price"
        price = 0.0
        try:
            price_el = card.locator('[class*="price"]').first
            price_text = await price_el.inner_text()
            price = _parse_price(price_text)
        except Exception:
            pass

        # Полный адрес: ищем строку «Москва, ...» в тексте всей карточки.
        # GeoLabel содержит только «Москва», полный адрес находится отдельной
        # строкой в теле карточки (например, «Москва, СВАО, р-н Лианозово, ...»).
        address = ""
        try:
            card_text = await card.inner_text()
            for line in card_text.split("\n"):
                line = line.strip()
                if line.startswith("Москва,") and len(line) > 12:
                    address = line
                    break
            # Запасной вариант — хотя бы GeoLabel
            if not address:
                geo_el = card.locator('[data-name="GeoLabel"]').first
                address = (await geo_el.inner_text()).strip()
        except Exception:
            pass


        # Метро и расстояние пешком
        metro_distance = 0
        metro_name = ""
        try:
            geo_el = card.locator('[data-name="SpecialGeo"]').first
            geo_text = await geo_el.inner_text()
            metro_distance = _parse_metro_distance(geo_text)
            lines = [ln.strip() for ln in geo_text.split("\n") if ln.strip()]
            if lines:
                metro_name = lines[0]
        except Exception:
            pass

        # Описание объявления (до 1000 символов)
        description = ""
        try:
            desc_el = card.locator('[data-name="Description"]').first
            description = (await desc_el.inner_text()).strip()[:1000]
        except Exception:
            pass

        # Первое фото из галереи
        image_url = ""
        try:
            img_el = card.locator("img").first
            image_url = await img_el.get_attribute("src") or ""
        except Exception:
            pass

        # Пропускаем карточки без цены или площади
        if price <= 0 or room_info["space"] <= 0:
            logger.debug(f"Пропускаем карточку {cian_id}: цена={price}, площадь={room_info['space']}")
            return None

        return {
            "cian_id": cian_id,
            "rooms": room_info["rooms"],
            "space": room_info["space"],
            "price": price,
            "floor": room_info["floor"],
            "max_floor": room_info["max_floor"],
            "address": address,
            "description": description,
            "image_url": image_url,
            "is_studio": room_info["is_studio"],
            "is_apartment": room_info["is_apartment"],
            "features": {
                "metro_distance_minutes": metro_distance,
                "metro_name": metro_name,
            },
        }

    except Exception as e:
        logger.warning(f"Ошибка при разборе карточки: {e}")
        return None


async def run_stealth_parser() -> None:
    """
    Фоновая задача стелс-парсинга объявлений с Циан.
    Запускается по расписанию через APScheduler (9:00, 15:00, 21:00).
    Использует резидентный прокси для обхода блокировок.
    Парсит реальные объявления с сайта (до 3 страниц за сессию).
    """
    logger.info("🚀 Запуск фонового парсинга квартир...")

    # Загружаем конфигурацию скоринга
    async with async_session_maker() as session:
        config_statement = select(ScoringConfiguration).where(ScoringConfiguration.is_active == True)
        config_result = await session.exec(config_statement)
        config = config_result.first()
        if not config:
            config = ScoringConfiguration()
            session.add(config)
            await session.commit()
            await session.refresh(config)

    # Настройка прокси
    proxy_config = None
    if settings.PROXY_URL:
        try:
            parsed = urlparse(settings.PROXY_URL)
            # Playwright поддерживает только http:// и socks5:// схемы для прокси
            proxy_config = {
                "server": f"http://{parsed.hostname}:{parsed.port}"
            }
            if parsed.username:
                proxy_config["username"] = parsed.username
            if parsed.password:
                proxy_config["password"] = parsed.password
            logger.info(f"Используется мобильный прокси: {parsed.hostname}:{parsed.port}")
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
                    "Запустите на сервере: <code>playwright install chromium</code>"
                )
                logger.error(err_msg)
                await send_telegram_alert(err_msg)
                return
            raise e

        context = await browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            viewport={"width": 1280, "height": 800}
        )

        page = await context.new_page()
        stealth = Stealth()
        await stealth.apply_stealth_async(page)

        all_parsed_data: list[dict] = []
        max_pages = 3
        base_url = "https://www.cian.ru/snyat-kvartiru/"

        for page_num in range(1, max_pages + 1):
            page_url = base_url if page_num == 1 else f"{base_url}p{page_num}/"
            logger.info(f"Переход на страницу {page_num}: {page_url}")

            try:
                # domcontentloaded вместо networkidle — Циан не заканчивает загрузку
                # фоновых ресурсов через прокси, поэтому networkidle никогда не наступает.
                await page.goto(page_url, wait_until="domcontentloaded", timeout=60000)
                await page.wait_for_timeout(4000)
            except Exception as e:
                logger.warning(f"Страница {page_num} не загрузилась: {e}")
                break

            cards = page.locator('article[data-name="CardComponent"]')
            card_count = await cards.count()
            logger.info(f"Страница {page_num}: найдено {card_count} карточек")

            if card_count == 0:
                logger.info("Карточек не найдено — завершаем пагинацию")
                break

            for i in range(card_count):
                data = await _extract_card_data(cards.nth(i))
                if data:
                    all_parsed_data.append(data)

            logger.info(f"Страница {page_num}: суммарно разобрано {len(all_parsed_data)} объявлений")

            if page_num < max_pages:
                await asyncio.sleep(3)

        logger.info(f"Всего собрано объявлений: {len(all_parsed_data)}")

        parsed_count = 0
        skipped_count = 0
        all_apts: list[Apartment] = []

        async with async_session_maker() as session:
            for data in all_parsed_data:
                if config.excludeStudios and data["is_studio"]:
                    skipped_count += 1
                    continue
                if config.excludeApartments and data["is_apartment"]:
                    skipped_count += 1
                    continue

                stmt = select(Apartment).where(Apartment.cian_id == data["cian_id"])
                res = await session.exec(stmt)
                apt = res.first()

                price_sqm = data["price"] / data["space"] if data["space"] > 0 else 0.0

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
                        description=data.get("description", ""),
                        image_url=data.get("image_url", ""),
                        is_studio=data["is_studio"],
                        is_apartment=data["is_apartment"],
                        features=data["features"],
                        created_at=datetime.utcnow(),
                        updated_at=datetime.utcnow(),
                    )
                else:
                    apt.price = data["price"]
                    apt.price_sqm = price_sqm
                    apt.floor = data["floor"]
                    apt.max_floor = data["max_floor"]
                    apt.address = data["address"]
                    apt.description = data.get("description", "")
                    apt.image_url = data.get("image_url", "")
                    apt.features = data["features"]
                    apt.updated_at = datetime.utcnow()

                session.add(apt)
                parsed_count += 1

            await session.commit()

            all_stmt = select(Apartment)
            all_res = await session.exec(all_stmt)
            all_apts = list(all_res.all())

            if all_apts:
                updated_apts = recalculate_scores(all_apts, config)
                for u_apt in updated_apts:
                    session.add(u_apt)
                await session.commit()

        success_msg = (
            f"✅ Парсинг завершён.\n"
            f"Новых/обновлённых: {parsed_count}, отфильтровано: {skipped_count}\n"
            f"Итого в базе: {len(all_apts)} объявлений"
        )
        logger.info(success_msg)
        await send_telegram_alert(success_msg)

    except Exception as e:
        err_msg = f"Критическая ошибка парсера: {e}"
        logger.exception(err_msg)
        await send_telegram_alert(err_msg)

    finally:
        if browser:
            await browser.close()
        if playwright_inst:
            await playwright_inst.stop()
