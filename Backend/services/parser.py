import asyncio
import logging
import re
import json
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any
from urllib.parse import urlparse

import httpx
from playwright.async_api import async_playwright
from playwright_stealth import Stealth
from sqlmodel import select

from core.config import settings
from core.db import async_session_maker
from core.scoring import recalculate_scores
from core.selectors_manager import selectors_manager
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

def find_value_recursive(data: Any, target_key: str) -> Any:
    """
    Рекурсивно ищет ключ во вложенных словарях и списках.
    """
    if isinstance(data, dict):
        if target_key in data:
            return data[target_key]
        for k, v in data.items():
            res = find_value_recursive(v, target_key)
            if res is not None:
                return res
    elif isinstance(data, list):
        for item in data:
            res = find_value_recursive(item, target_key)
            if res is not None:
                return res
    return None


def extract_district(address: str) -> Optional[str]:
    """
    Извлекает название района Москвы из строки адреса.
    """
    match = re.search(r"р-н\s+([^,]+)", address)
    if match:
        return match.group(1).strip()
    return None


def extract_okrug(address: str) -> str:
    """
    Определяет административный округ Москвы (АО) на основе адреса.
    """
    okrugs = [
        "СВАО", "ЮВАО", "ЮЗАО", "СЗАО",
        "ЦАО", "САО", "ВАО", "ЮАО", "ЗАО",
        "ТАО", "НАО", "Зеленоград"
    ]
    for okrug in okrugs:
        if okrug in address:
            return okrug
            
    full_names = [
        ("Северо-Восточный административный округ", "СВАО"),
        ("Юго-Восточный административный округ",   "ЮВАО"),
        ("Северо-Западный административный округ", "СЗАО"),
        ("Юго-Западный административный округ",    "ЮЗАО"),
        ("Центральный административный округ",     "ЦАО"),
        ("Северный административный округ",        "САО"),
        ("Восточный административный округ",       "ВАО"),
        ("Южный административный округ",           "ЮАО"),
        ("Западный административный округ",        "ЗАО"),
        ("Троицкий административный округ",        "ТАО"),
        ("Новомосковский административный округ",  "НАО"),
        ("Зеленоградский административный округ",  "Зеленоград"),
    ]
    for full_name, okrug in full_names:
        if full_name in address:
            return okrug
            
    known_districts = {
        # ЦАО
        "Арбат": "ЦАО", "Басманный": "ЦАО", "Замоскворечье": "ЦАО",
        "Красносельский": "ЦАО", "Мещанский": "ЦАО", "Пресня": "ЦАО",
        "Пресненский": "ЦАО", "Таганский": "ЦАО", "Тверской": "ЦАО",
        "Хамовники": "ЦАО", "Якиманка": "ЦАО",
        # САО
        "Аэропорт": "САО", "Беговой": "САО", "Бескудниковский": "САО",
        "Войковский": "САО", "Восточное Дегунино": "САО", "Головинский": "САО",
        "Дмитровский": "САО", "Западное Дегунино": "САО", "Коптево": "САО",
        "Левобережный": "САО", "Молжаниновский": "САО", "Савёловский": "САО",
        "Сокол": "САО", "Тимирязевский": "САО", "Ховрино": "САО", "Хорошёвский": "САО",
        # СВАО
        "Алексеевский": "СВАО", "Алтуфьевский": "СВАО", "Бабушкинский": "СВАО",
        "Бибирево": "СВАО", "Бутырский": "СВАО", "Лианозово": "СВАО",
        "Лосиноостровский": "СВАО", "Марфино": "СВАО", "Марьина роща": "СВАО",
        "Останкинский": "СВАО", "Отрадное": "СВАО", "Ростокино": "СВАО",
        "Свиблово": "СВАО", "Северное Медведково": "СВАО", "Северный": "СВАО",
        "Южное Медведково": "СВАО", "Ярославский": "СВАО",
        # ВАО
        "Богородское": "ВАО", "Вешняки": "ВАО", "Восточное Измайлово": "ВАО",
        "Восточный": "ВАО", "Гольяново": "ВАО", "Ивановское": "ВАО",
        "Измайлово": "ВАО", "Косино-Ухтомский": "ВАО", "Метрогородок": "ВАО",
        "Новогиреево": "ВАО", "Новокосино": "ВАО", "Перово": "ВАО",
        "Преображенское": "ВАО", "Северное Измайлово": "ВАО",
        "Соколиная Гора": "ВАО", "Сокольники": "ВАО",
        # ЮВАО
        "Выхино-Жулебино": "ЮВАО", "Капотня": "ЮВАО", "Кузьминки": "ЮВАО",
        "Лефортово": "ЮВАО", "Нижегородский": "ЮВАО", "Текстильщики": "ЮВАО",
        "Рязанский": "ЮВАО", "Люблино": "ЮВАО", "Марьино": "ЮВАО",
        "Некрасовка": "ЮВАО", "Нижегородский": "ЮВАО", "Печатники": "ЮВАО",
        "Рязанский": "ЮВАО", "Текстильщики": "ЮВАО", "Южнопортовый": "ЮВАО",
        # ЮАО
        "Бирюлёво Восточное": "ЮАО", "Бирюлёво Западное": "ЮАО",
        "Братеево": "ЮАО", "Даниловский": "ЮАО", "Донской": "ЮАО",
        "Зябликово": "ЮАО", "Москворечье-Сабурово": "ЮАО", "Нагатино-Садовники": "ЮАО",
        "Нагатинский Затон": "ЮАО", "Нагорный": "ЮАО", "Орехово-Борисово Северное": "ЮАО",
        "Орехово-Борисово Южное": "ЮАО", "Царицыно": "ЮАО", "Чертаново Северное": "ЮАО",
        "Чертаново Центральное": "ЮАО", "Чертаново Южное": "ЮАО",
        # ЮЗАО
        "Академический": "ЮЗАО", "Гагаринский": "ЮЗАО",
        "Зюзино": "ЮЗАО", "Коньково": "ЮЗАО", "Котловка": "ЮЗАО",
        "Ломоносовский": "ЮЗАО", "Обручевский": "ЮЗАО", "Северное Бутово": "ЮЗАО",
        "Тёплый Стан": "ЮЗАО", "Черёмушки": "ЮЗАО", "Южное Бутово": "ЮЗАО",
        "Ясенево": "ЮЗАО",
        # ЗАО
        "Внуково": "ЗАО", "Дорогомилово": "ЗАО", "Крылатское": "ЗАО", "Кунцево": "ЗАО",
        "Можайский": "ЗАО", "Ново-Переделкино": "ЗАО", "Очаково-Матвеевское": "ЗАО",
        "Проспект Вернадского": "ЗАО", "Раменки": "ЗАО", "Солнцево": "ЗАО",
        "Тропарёво-Никулино": "ЗАО", "Филёвский Парк": "ЗАО", "Фили-Давыдково": "ЗАО",
        # СЗАО
        "Куркино": "СЗАО", "Митино": "СЗАО", "Покровское-Стрешнево": "СЗАО",
        "Северное Тушино": "СЗАО", "Строгино": "СЗАО", "Хорошёво-Мнёвники": "СЗАО",
        "Щукино": "СЗАО", "Южное Тушино": "СЗАО"
    }
    
    district_name = extract_district(address)
    if district_name and district_name in known_districts:
        return known_districts[district_name]
        
    sorted_districts = sorted(known_districts.keys(), key=len, reverse=True)
    for district in sorted_districts:
        if district in address:
            return known_districts[district]
            
    return "Москва"


def parse_views_formatted_string(text: str) -> tuple[Optional[int], Optional[int]]:
    """
    Разбирает строку просмотров Циан вида «148 просмотров, 2 за сегодня» или «нет за сегодня».
    Поддерживает фразу «нет за сегодня» (интерпретируя её как 0) и извлекает
    общее число просмотров, даже если сегодняшние просмотры отсутствуют.
    """
    total = None
    today = None
    
    if not text:
        return total, today

    # Нормализуем пробельные символы (включая неразрывные пробелы)
    cleaned_text = re.sub(r"[\s\xa0\u202f]+", " ", text).strip()

    # 1. Поиск общего количества просмотров
    total_match = re.search(r"(\d[\d\s]*)\s*просмотр", cleaned_text, re.IGNORECASE)
    if total_match:
        try:
            total_cleaned = re.sub(r"\s", "", total_match.group(1))
            total = int(total_cleaned)
        except Exception:
            pass

    # 2. Поиск сегодняшних просмотров
    today_match = re.search(r"(\d+|нет)\s*за сегодня", cleaned_text, re.IGNORECASE)
    if today_match:
        today_str = today_match.group(1).lower()
        if today_str == "нет":
            today = 0
        else:
            try:
                today = int(today_str)
            except Exception:
                pass

    return total, today



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

    if "студия" in low or "studio" in low:
        result["is_studio"] = True
        result["rooms"] = 1
    else:
        m = re.search(r"(\d+)-комн", low)
        if m:
            result["rooms"] = int(m.group(1))

    if "апартамент" in low:
        result["is_apartment"] = True

    m = re.search(r"([\d]+[,\.]?[\d]*)\s*м²", text)
    if m:
        result["space"] = float(m.group(1).replace(",", "."))

    m = re.search(r"(\d+)/(\d+)\s*этаж", text)
    if m:
        result["floor"] = int(m.group(1))
        result["max_floor"] = int(m.group(2))

    return result


def _parse_price(text: str) -> float:
    """
    Разбирает строку вида «600 000 ₽» → 600000.0.
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


def generate_semantic_tags(apt: Apartment) -> List[str]:
    """
    Генерирует семантические теги на основе характеристик квартиры, аналогично macOS клиенту.
    """
    tags = []
    
    if apt.is_studio:
        tags.append("Студия")
    elif apt.rooms:
        if apt.rooms >= 4:
            tags.append("4+ комн.")
        else:
            tags.append(f"{apt.rooms}-комн.")
            
    if apt.metro_distance_minutes:
        if apt.metro_distance_minutes <= 5:
            tags.append("до 5 мин")
        elif apt.metro_distance_minutes <= 10:
            tags.append("до 10 мин")
        elif apt.metro_distance_minutes <= 15:
            tags.append("до 15 мин")
        else:
            tags.append("> 15 мин")
            
    if apt.floor and apt.max_floor:
        if apt.floor == 1:
            tags.append("Первый этаж")
        elif apt.floor == apt.max_floor:
            tags.append("Последний этаж")
        elif apt.floor == apt.max_floor - 1:
            tags.append("Предпоследний этаж")
            
    if apt.space:
        if apt.space < 30:
            tags.append("до 30 м²")
        elif apt.space <= 50:
            tags.append("30-50 м²")
        elif apt.space <= 70:
            tags.append("50-70 м²")
        else:
            tags.append("> 70 м²")
            
    if apt.is_auction: tags.append("Аукцион")
    if apt.is_alternative: tags.append("Альтернатива")
    if apt.is_share: tags.append("Доля")
    if apt.is_apartment: tags.append("Апартаменты")
    if apt.is_paid_promotion:
        tags.append(f"Продвижение ({apt.promotion_type or ''})")
        
    return tags


def update_views_snapshot(apt: Apartment, old_views_total: Optional[int], old_last_update: datetime) -> None:
    """
    Фиксирует снэпшот просмотров для расчета суточной дельты, аналогично клиенту.
    """
    if old_views_total is not None and apt.views_total is not None and apt.views_total > old_views_total:
        prev_date = apt.previous_views_date or datetime.min
        if (datetime.utcnow() - prev_date).total_seconds() > 20 * 3600:
            apt.previous_views_total = old_views_total
            apt.previous_views_date = old_last_update
    elif apt.previous_views_total is None and apt.views_total is not None:
        apt.previous_views_total = apt.views_total
        apt.previous_views_date = old_last_update


async def _extract_card_data(card) -> Optional[dict]:
    """
    Извлекает базовые поля квартиры из карточки на странице поиска.
    """
    try:
        href = await card.locator("a").first.get_attribute("href") or ""
        m = re.search(r"/flat/(\d+)/", href)
        if not m:
            return None
        cian_id = m.group(1)

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

        price = 0.0
        try:
            price_el = card.locator('[class*="price"]').first
            price_text = await price_el.inner_text()
            price = _parse_price(price_text)
        except Exception:
            pass

        address = ""
        try:
            card_text = await card.inner_text()
            for line in card_text.split("\n"):
                line = line.strip()
                if line.startswith("Москва,") and len(line) > 12:
                    address = line
                    break
            if not address:
                geo_el = card.locator('[data-name="GeoLabel"]').first
                address = (await geo_el.inner_text()).strip()
        except Exception:
            pass

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

        description = ""
        try:
            desc_el = card.locator('[data-name="Description"]').first
            description = (await desc_el.inner_text()).strip()[:1000]
        except Exception:
            pass

        image_url = ""
        try:
            img_el = card.locator("img").first
            image_url = await img_el.get_attribute("src") or ""
        except Exception:
            pass

        if price <= 0 or room_info["space"] <= 0:
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


# ---------------------------------------------------------------------------
# Глубокий парсинг детальной страницы
# ---------------------------------------------------------------------------

async def parse_detail_page(page, cian_id: str) -> dict:
    """
    Открывает детальную страницу квартиры и собирает подробные характеристики,
    сначала пытаясь разобрать JSON __NEXT_DATA__, затем через HTML CSS локаторы.
    """
    url = f"https://www.cian.ru/sale/flat/{cian_id}/"
    logger.info(f"🔍 Переход на детальную страницу {cian_id}: {url}")
    
    try:
        await page.goto(url, wait_until="domcontentloaded", timeout=45000)
        # Небольшая задержка, имитирующая пользователя
        await page.wait_for_timeout(2500)
        
        # Динамическое ожидание загрузки блока статистики
        try:
            await page.get_by_text(re.compile("просмотр", re.IGNORECASE)).first.wait_for(state="attached", timeout=5000)
            logger.info(f"📊 Блок статистики просмотров успешно загружен на странице {cian_id}")
        except Exception as e:
            logger.warning(f"⚠️ Не дождались загрузки блока статистики (текст 'просмотр') для {cian_id}: {e}")
            
    except Exception as e:
        logger.warning(f"⚠️ Не удалось загрузить детальную страницу {cian_id}: {e}")
        return {}

        
    detail_data = {}
    
    # 1. Попытка извлечения __NEXT_DATA__
    try:
        json_str = await page.evaluate('() => document.getElementById("__NEXT_DATA__")?.textContent')
        if json_str:
            json_obj = json.loads(json_str)
            offer_data = find_value_recursive(json_obj, "offerData")
            if offer_data:
                offer = offer_data.get("offer", offer_data)
                
                # Извлечение bargainTerms и цены
                bargain_terms = offer.get("bargainTerms", {})
                price = (
                    bargain_terms.get("price") or 
                    bargain_terms.get("priceRur") or 
                    bargain_terms.get("priceTotal") or 
                    bargain_terms.get("priceTotalRur")
                )
                if price:
                    detail_data["price"] = float(price)
                    
                detail_data["title"] = offer.get("title") or offer.get("fullName")
                detail_data["space"] = offer.get("totalArea") or offer.get("area")
                detail_data["living_space"] = offer.get("livingArea")
                detail_data["kitchen_space"] = offer.get("kitchenArea")
                detail_data["floor"] = offer.get("floorNumber") or offer.get("floor")
                detail_data["rooms"] = offer.get("roomsCount") or offer.get("rooms")
                detail_data["description"] = offer.get("description") or offer.get("text")
                
                # Фотографии
                photos = offer.get("photos") or offer.get("images") or []
                image_urls = []
                if isinstance(photos, list):
                    for photo in photos:
                        if isinstance(photo, dict):
                            img_url = photo.get("fullUrl") or photo.get("url") or photo.get("src")
                            if img_url:
                                image_urls.append(img_url)
                                
                # Если фото мало, пробуем регуляркой по всей строке JSON
                if len(image_urls) < 3:
                    brute_urls = re.findall(r"https://cdn-p\.cian\.site/[^\s\"']+\.jpg", json_str)
                    image_urls.extend(brute_urls)
                    
                image_urls = list(dict.fromkeys(image_urls)) # убираем дубли
                detail_data["image_urls"] = image_urls
                if image_urls:
                    detail_data["image_url"] = image_urls[0]
                    
                # Здание
                building = offer.get("building") or {}
                detail_data["max_floor"] = building.get("floorsCount") or building.get("floors")
                detail_data["year_built"] = building.get("buildYear") or building.get("year")
                detail_data["house_material"] = building.get("materialType") or building.get("material")
                detail_data["parking"] = building.get("parking")
                
                lifts = building.get("passenger_lifts_count") or building.get("lifts")
                if lifts:
                    try:
                        lifts_int = int(lifts)
                        detail_data["elevator"] = f"{lifts_int} шт." if lifts_int > 0 else None
                    except (ValueError, TypeError):
                        detail_data["elevator"] = str(lifts)
                        
                # Другие характеристики
                detail_data["ceiling_height"] = offer.get("ceilingHeight")
                detail_data["bathroom_type"] = offer.get("bathroomType")
                detail_data["balcony"] = offer.get("balconyType") or offer.get("balcony")
                detail_data["repair"] = offer.get("repairType") or offer.get("repair")
                detail_data["furniture"] = offer.get("hasFurniture")
                detail_data["window_view"] = offer.get("windowView")
                
                # Адрес
                geo = offer.get("geo") or {}
                address_comps = []
                if isinstance(geo.get("address"), list):
                    for item in geo["address"]:
                        if isinstance(item, dict):
                            comp = item.get("fullName") or item.get("title") or item.get("name")
                            if comp:
                                address_comps.append(comp)
                if address_comps:
                    detail_data["address"] = ", ".join(address_comps)
                else:
                    detail_data["address"] = geo.get("displayAddress") or geo.get("userInputAddress")
                    
                # Метро
                undergrounds = geo.get("undergrounds") or []
                if undergrounds and isinstance(undergrounds, list):
                    metro = undergrounds[0]
                    if isinstance(metro, dict):
                        detail_data["metro_name"] = metro.get("name") or metro.get("title")
                        detail_data["metro_distance_minutes"] = metro.get("travelTime") or metro.get("time") or metro.get("distance")
                        detail_data["metro_transport_type"] = metro.get("travelType") or metro.get("transportType")
                        
                # Статистика
                stats = offer.get("stats") or {}
                detail_data["views_total"] = stats.get("total") or stats.get("totalViews") or stats.get("allViews")
                detail_data["views_today"] = (
                    stats.get("daily") or 
                    stats.get("dailyViews") or 
                    stats.get("today") or 
                    stats.get("todayViews") or 
                    stats.get("viewsToday") or 
                    stats.get("dayViews")
                )
                
                # Разбор строки просмотров, если нет в полях
                if not detail_data.get("views_total") or not detail_data.get("views_today"):
                    formatted_str = stats.get("totalViewsFormattedString") or offer.get("totalViewsFormattedString")
                    if formatted_str:
                        total, today = parse_views_formatted_string(formatted_str)
                        if total: detail_data["views_total"] = total
                        if today: detail_data["views_today"] = today
                        
                # Особые условия
                sale_type = str(bargain_terms.get("saleType") or offer.get("saleType") or "").lower()
                desc_lower = (detail_data.get("description") or "").lower()
                
                detail_data["is_auction"] = bool(
                    offer.get("isAuction") or 
                    "auction" in sale_type or 
                    "аукцион" in desc_lower or
                    (detail_data.get("title") and "аукцион" in detail_data["title"].lower())
                )
                detail_data["is_alternative"] = "alternative" in sale_type
                
                category = str(offer.get("category") or "").lower()
                flat_type = str(offer.get("flatType") or "").lower()
                detail_data["is_studio"] = "studio" in flat_type or "studio" in category or "студия" in desc_lower
                detail_data["is_apartment"] = "apartment" in category or "апартамент" in desc_lower
                detail_data["is_share"] = "share" in category or "доля" in desc_lower
                
                deposit_phrases = [
                    "залог внесен", "залог внесён", "задаток внесен", "задаток внесён",
                    "аванс внесен", "аванс внесён", "внесен залог", "внесён залог",
                    "внесен задаток", "внесён задаток", "внесен аванс", "внесён аванс",
                    "под авансом", "принят аванс", "получен аванс", "взяли аванс", "дали аванс",
                    "под залогом", "принят залог", "получен залог",
                    "под бронью", "квартира забронирована", "забронировано", "бронь до"
                ]
                detail_data["is_deposit_paid"] = any(p in desc_lower for p in deposit_phrases)
                
                # Продвижение
                placement = str(offer.get("placementType") or offer.get("promotionType") or "").lower()
                if placement and placement not in ("simple", "organic", "none"):
                    detail_data["is_paid_promotion"] = True
                    detail_data["promotion_type"] = placement
                    
                # Дата публикации
                pub_date_str = offer.get("publishedDate")
                if pub_date_str:
                    try:
                        detail_data["published_date"] = datetime.fromisoformat(pub_date_str.replace("Z", "+00:00"))
                    except Exception:
                        pass
                elif offer.get("addedTimestamp"):
                    try:
                        detail_data["published_date"] = datetime.utcfromtimestamp(float(offer["addedTimestamp"]))
                    except Exception:
                        pass
                        
                # Продавец
                seller = offer.get("seller") or offer.get("agent") or {}
                detail_data["seller_name"] = seller.get("name") or seller.get("alias") or seller.get("companyName")
                detail_data["seller_type"] = seller.get("type") or seller.get("category")
                
                detail_data["is_detailed_parsed"] = True
                
                if detail_data.get("address"):
                    detail_data["okrug"] = extract_okrug(detail_data["address"])
                    detail_data["district"] = extract_district(detail_data["address"])
                    
                return detail_data
    except Exception as e:
        logger.warning(f"⚠️ Ошибка разбора JSON на детальной странице {cian_id}: {e}")

    # 2. Попытка извлечения через HTML селекторы
    selectors = selectors_manager.config["detail"]
    try:
        # Описание
        for selector in selectors["descriptionSelectors"]:
            loc = page.locator(selector)
            if await loc.count() > 0:
                detail_data["description"] = (await loc.first.inner_text()).strip()
                break
                
        # Адрес
        for selector in selectors["addressSelectors"]:
            loc = page.locator(selector)
            if await loc.count() > 0:
                detail_data["address"] = (await loc.first.inner_text()).strip()
                break
                
        if detail_data.get("address"):
            detail_data["okrug"] = extract_okrug(detail_data["address"])
            detail_data["district"] = extract_district(detail_data["address"])
            
        # Метро
        for selector in selectors["metroSelectors"]:
            loc = page.locator(selector)
            if await loc.count() > 0:
                detail_data["metro_name"] = (await loc.first.inner_text()).strip().split("\n")[0]
                break
                
        # Продавец
        for selector in selectors["sellerSelectors"]:
            loc = page.locator(selector)
            if await loc.count() > 0:
                detail_data["seller_name"] = (await loc.first.inner_text()).strip()
                break
                
        # Характеристики
        characteristics_selectors = selectors["mainCharacteristicsSelectors"]
        title_sel = selectors["mainCharacteristicsTitleSelector"]
        val_sel = selectors["mainCharacteristicsValueSelector"]
        
        for selector in characteristics_selectors:
            loc = page.locator(selector)
            count = await loc.count()
            if count > 0:
                for i in range(count):
                    item = loc.nth(i)
                    title = ""
                    value = ""
                    try:
                        title_loc = item.locator(title_sel)
                        val_loc = item.locator(val_sel)
                        if await title_loc.count() > 0:
                            title = (await title_loc.first.inner_text()).strip().lower()
                        if await val_loc.count() > 0:
                            value = (await val_loc.first.inner_text()).strip()
                    except Exception:
                        pass
                        
                    if not title or not value:
                        try:
                            text_val = await item.inner_text()
                            parts = text_val.split("\n")
                            if len(parts) >= 2:
                                title = parts[0].strip().lower()
                                value = parts[1].strip()
                        except Exception:
                            pass
                            
                    if title and value:
                        if "общая" in title:
                            try: detail_data["space"] = float(re.sub(r"[^\d\.]", "", value.replace(",", ".")))
                            except Exception: pass
                        elif "жилая" in title:
                            try: detail_data["living_space"] = float(re.sub(r"[^\d\.]", "", value.replace(",", ".")))
                            except Exception: pass
                        elif "кухня" in title:
                            try: detail_data["kitchen_space"] = float(re.sub(r"[^\d\.]", "", value.replace(",", ".")))
                            except Exception: pass
                        elif "этаж" in title:
                            m = re.search(r"(\d+)/(\d+)", value)
                            if m:
                                try:
                                    detail_data["floor"] = int(m.group(1))
                                    detail_data["max_floor"] = int(m.group(2))
                                except Exception: pass
                            else:
                                m = re.search(r"\d+", value)
                                if m:
                                    try: detail_data["floor"] = int(m.group(0))
                                    except Exception: pass
                        elif "построен" in title or "год постройки" in title:
                            try: detail_data["year_built"] = int(re.search(r"\d+", value).group(0))
                            except Exception: pass
                        elif "высота потолков" in title:
                            try: detail_data["ceiling_height"] = float(re.sub(r"[^\d\.]", "", value.replace(",", ".")))
                            except Exception: pass
                        elif "тип дома" in title or "материал" in title:
                            detail_data["house_material"] = value
                        elif "ремонт" in title:
                            detail_data["repair"] = value
                        elif "мебель" in title:
                            detail_data["furniture"] = "да" in value.lower() or "есть" in value.lower()
                        elif "балкон" in title or "лоджия" in title:
                            detail_data["balcony"] = value
                        elif "санузел" in title:
                            detail_data["bathroom_type"] = value
                        elif "лифт" in title:
                            detail_data["elevator"] = value
                        elif "парковка" in title:
                            detail_data["parking"] = value
                break
                
        # Семантические теги и особые условия по описанию
        if detail_data.get("description"):
            desc_lower = detail_data["description"].lower()
            deposit_phrases = [
                "залог внесен", "залог внесён", "задаток внесен", "задаток внесён",
                "аванс внесен", "аванс внесён", "внесен залог", "внесён залог",
                "внесен задаток", "внесён задаток", "внесен аванс", "внесён аванс",
                "под авансом", "принят аванс", "получен аванс", "взяли аванс", "дали аванс"
            ]
            detail_data["is_deposit_paid"] = any(p in desc_lower for p in deposit_phrases)
            if "аукцион" in desc_lower: detail_data["is_auction"] = True
            if "студия" in desc_lower: detail_data["is_studio"] = True
            if "апартамент" in desc_lower: detail_data["is_apartment"] = True
            if "доля" in desc_lower: detail_data["is_share"] = True
            
        # DOM Fallback для просмотров
        if not detail_data.get("views_total") or not detail_data.get("views_today"):
            logger.info(f"🔄 Запуск DOM Fallback для извлечения просмотров (cian_id: {cian_id})...")
            fallback_selectors = ['[data-name*="Views"]', '[data-name*="Stats"]']
            views_found = False
            for selector in fallback_selectors:
                loc = page.locator(selector)
                count = await loc.count()
                for i in range(count):
                    try:
                        text = await loc.nth(i).inner_text()
                        if text:
                            total, today = parse_views_formatted_string(text)
                            if total is not None:
                                detail_data["views_total"] = total
                                views_found = True
                            if today is not None:
                                detail_data["views_today"] = today
                                views_found = True
                            if views_found:
                                logger.info(f"📊 Просмотры найдены через селектор {selector}: {text} -> total: {total}, today: {today}")
                                break
                    except Exception as ex:
                        logger.warning(f"Ошибка при разборе текста из селектора {selector}: {ex}")
                if views_found:
                    break

            # Попытка поиска по текстовому содержимому всей страницы (BeautifulSoup)
            if not detail_data.get("views_total") or not detail_data.get("views_today"):
                try:
                    from bs4 import BeautifulSoup
                    html_content = await page.content()
                    soup = BeautifulSoup(html_content, "html.parser")
                    page_text = soup.get_text()
                    lines = [line.strip() for line in page_text.split("\n") if line.strip()]
                    for line in lines:
                        if "просмотр" in line.lower() or "за сегодня" in line.lower():
                            total, today = parse_views_formatted_string(line)
                            if total is not None:
                                detail_data["views_total"] = total
                                views_found = True
                            if today is not None:
                                detail_data["views_today"] = today
                                views_found = True
                            if views_found:
                                logger.info(f"📊 Просмотры найдены через BeautifulSoup get_text() построчно: {line} -> total: {total}, today: {today}")
                                break

                    # Резервный вариант на случай, если информация разбита переносами строк
                    if not detail_data.get("views_total") or not detail_data.get("views_today"):
                        single_line_text = re.sub(r"\s+", " ", page_text)
                        match = re.search(r".{0,50}просмотр.{0,50}", single_line_text, re.IGNORECASE)
                        if match:
                            snippet = match.group(0)
                            total, today = parse_views_formatted_string(snippet)
                            if total is not None:
                                detail_data["views_total"] = total
                            if today is not None:
                                detail_data["views_today"] = today
                            logger.info(f"📊 Просмотры найдены в текстовом сниппете: {snippet} -> total: {total}, today: {today}")
                except Exception as ex:
                    logger.warning(f"⚠️ Ошибка при извлечении просмотров через BeautifulSoup: {ex}")

        if detail_data.get("address") or detail_data.get("description"):
            detail_data["is_detailed_parsed"] = True

            
    except Exception as e:
        logger.warning(f"⚠️ Ошибка разбора HTML селекторов для {cian_id}: {e}")
        
    # Попытка определить дату создания из HTML, если её нет в detail_data
    if not detail_data.get("published_date"):
        try:
            html_content = await page.content()
            pub_match = re.search(r'"publishedDate"\s*:\s*"([^"]+)"', html_content)
            if pub_match and len(pub_match.group(1)) >= 10:
                detail_data["published_date"] = datetime.fromisoformat(pub_match.group(1).replace("Z", "+00:00"))
            else:
                ts_match = re.search(r'"addedTimestamp"\s*:\s*(\d+)', html_content)
                if ts_match:
                    detail_data["published_date"] = datetime.utcfromtimestamp(float(ts_match.group(1)))
        except Exception as e:
            logger.warning(f"⚠️ Ошибка при поиске даты публикации в HTML для {cian_id}: {e}")

    # Запрос детальной статистики просмотров в контексте Playwright
    if "published_date" in detail_data and detail_data["published_date"]:
        try:
            date_str = detail_data["published_date"].strftime("%Y-%m-%d")
            stat_url = f"https://api.cian.ru/offer-card/v1/get-offer-card-statistic/?offerCreationDate={date_str}&offerId={cian_id}"
            logger.info(f"📊 Запрос детальной статистики просмотров для {cian_id}: {stat_url}")
            
            views_history = await page.evaluate("""async (url) => {
                try {
                    const response = await fetch(url);
                    if (!response.ok) {
                        return JSON.stringify({ error: `HTTP ${response.status}: ${response.statusText}` });
                    }
                    return await response.text();
                } catch (e) {
                    return JSON.stringify({ error: e.toString() });
                }
            }""", stat_url)
            
            detail_data["views_history_json"] = views_history
            logger.info(f"✅ Получена детальная статистика просмотров для {cian_id}")
        except Exception as ev:
            logger.warning(f"⚠️ Не удалось загрузить детальную статистику просмотров для {cian_id} через evaluate: {ev}")

    return detail_data


# ---------------------------------------------------------------------------
# Главная задача парсера
# ---------------------------------------------------------------------------

async def run_stealth_parser() -> None:
    """
    Фоновая задача стелс-парсинга объявлений о продаже квартир с Циан.
    Парсит детальные страницы квартир и заполняет расширенные характеристики.
    """
    logger.info("🚀 Запуск глубокого фонового парсинга квартир...")

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

    # Дефолтные URL поиска (могут быть переопределены внешне, но эти соответствуют macOS-клиенту)
    search_urls = [
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=9&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order",
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=8&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order",
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=10&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order",
        "https://www.cian.ru/cat.php?deal_type=sale&district%5B0%5D=7&electronic_trading=2&engine_version=2&flat_share=2&floornl=1&foot_min=7&is_first_floor=0&minfloorn=5&offer_type=flat&only_foot=2&repair%5B0%5D=1&sort=price_object_order"
    ]

    proxy_config = None
    if settings.PROXY_URL:
        try:
            parsed = urlparse(settings.PROXY_URL)
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

        all_parsed_cards: list[dict] = []
        max_pages = 2  # Ограничиваемся 2 страницами на каждый поисковый URL для безопасности
        
        # Шаг 1: Сбор карточек со страниц поиска
        for s_url in search_urls:
            logger.info(f"🔎 Сканирование поискового URL: {s_url}")
            for page_num in range(1, max_pages + 1):
                # Добавляем параметр p к URL
                if page_num == 1:
                    page_url = s_url
                else:
                    parsed_url = urlparse(s_url)
                    query = parsed_url.query
                    if "p=" in query:
                        query = re.sub(r"p=\d+", f"p={page_num}", query)
                    else:
                        query = f"{query}&p={page_num}" if query else f"p={page_num}"
                    page_url = parsed_url._replace(query=query).geturl()
                    
                logger.info(f"Переход на страницу {page_num}: {page_url}")

                try:
                    await page.goto(page_url, wait_until="domcontentloaded", timeout=45000)
                    await page.wait_for_timeout(3000)
                except Exception as e:
                    logger.warning(f"Страница {page_num} не загрузилась: {e}")
                    break

                cards = page.locator('article[data-name="CardComponent"]')
                card_count = await cards.count()
                logger.info(f"Найдено {card_count} карточек на странице {page_num}")

                if card_count == 0:
                    break

                for i in range(card_count):
                    data = await _extract_card_data(cards.nth(i))
                    if data:
                        all_parsed_cards.append(data)

                await asyncio.sleep(2)

        logger.info(f"Сбор карточек завершен. Всего найдено уникальных: {len({c['cian_id'] for c in all_parsed_cards})}")

        # Шаг 2: Глубокий парсинг детальных страниц
        parsed_count = 0
        skipped_count = 0
        
        # Ограничиваем количество детальных парсингов за один проход, чтобы избежать бана
        max_detailed_scrapes = 40
        detailed_scrapes_count = 0

        async with async_session_maker() as session:
            for card_data in all_parsed_cards:
                cian_id = card_data["cian_id"]
                
                # Ищем квартиру в БД
                stmt = select(Apartment).where(Apartment.cian_id == cian_id)
                res = await session.exec(stmt)
                apt = res.first()
                
                needs_detail_parse = False
                if not apt:
                    needs_detail_parse = True
                elif not apt.is_detailed_parsed:
                    needs_detail_parse = True
                else:
                    # Если квартира распарсена детально, но давно (например, более 24 часов назад)
                    time_passed = (datetime.utcnow() - apt.updated_at).total_seconds()
                    if time_passed > 24 * 3600:
                        needs_detail_parse = True

                # Ограничение на количество детальных переходов
                if needs_detail_parse and detailed_scrapes_count >= max_detailed_scrapes:
                    logger.info(f"Достигнут лимит детальных парсингов ({max_detailed_scrapes}). Пропускаем глубокий парсинг для {cian_id}.")
                    needs_detail_parse = False

                detail_info = {}
                if needs_detail_parse:
                    # Выполняем переход на детальную страницу
                    detail_info = await parse_detail_page(page, cian_id)
                    detailed_scrapes_count += 1
                    await asyncio.sleep(2.5) # Пауза между детальными страницами
                
                # Объединяем данные из карточки и детальной страницы
                # Детальная страница имеет приоритет
                merged_data = {**card_data, **detail_info}

                if config.excludeStudios and merged_data.get("is_studio", False):
                    skipped_count += 1
                    continue
                if config.excludeApartments and merged_data.get("is_apartment", False):
                    skipped_count += 1
                    continue

                price_sqm = merged_data["price"] / merged_data["space"] if merged_data["space"] > 0 else 0.0
                
                if not apt:
                    # Создаем новую запись
                    apt = Apartment(
                        cian_id=cian_id,
                        title=merged_data.get("title", f"{merged_data['rooms']}-комн. квартира, {merged_data['space']} м²"),
                        rooms=merged_data["rooms"],
                        space=merged_data["space"],
                        price=merged_data["price"],
                        price_sqm=price_sqm,
                        floor=merged_data["floor"],
                        max_floor=merged_data["max_floor"],
                        address=merged_data["address"],
                        url=f"https://www.cian.ru/sale/flat/{cian_id}/",
                        description=merged_data.get("description", ""),
                        image_url=merged_data.get("image_url", ""),
                        image_urls=merged_data.get("image_urls", []),
                        living_space=merged_data.get("living_space"),
                        kitchen_space=merged_data.get("kitchen_space"),
                        house_material=merged_data.get("house_material"),
                        year_built=merged_data.get("year_built"),
                        ceiling_height=merged_data.get("ceiling_height"),
                        bathroom_type=merged_data.get("bathroom_type"),
                        balcony=merged_data.get("balcony"),
                        window_view=merged_data.get("window_view"),
                        repair=merged_data.get("repair"),
                        furniture=merged_data.get("furniture"),
                        metro_name=merged_data.get("metro_name") or merged_data.get("features", {}).get("metro_name"),
                        metro_distance_minutes=merged_data.get("metro_distance_minutes") or merged_data.get("features", {}).get("metro_distance_minutes"),
                        metro_transport_type=merged_data.get("metro_transport_type"),
                        parking=merged_data.get("parking"),
                        elevator=merged_data.get("elevator"),
                        seller_name=merged_data.get("seller_name"),
                        seller_type=merged_data.get("seller_type"),
                        views_today=merged_data.get("views_today"),
                        views_total=merged_data.get("views_total"),
                        published_date=merged_data.get("published_date"),
                        views_history_json=merged_data.get("views_history_json"),
                        is_studio=merged_data.get("is_studio", False),
                        is_apartment=merged_data.get("is_apartment", False),
                        is_auction=merged_data.get("is_auction", False),
                        is_deposit_paid=merged_data.get("is_deposit_paid", False),
                        is_alternative=merged_data.get("is_alternative", False),
                        is_share=merged_data.get("is_share", False),
                        is_paid_promotion=merged_data.get("is_paid_promotion", False),
                        promotion_type=merged_data.get("promotion_type"),
                        okrug=merged_data.get("okrug"),
                        district=merged_data.get("district"),
                        is_detailed_parsed=merged_data.get("is_detailed_parsed", False),
                        features=merged_data.get("features", {}),
                        created_at=datetime.utcnow(),
                        updated_at=datetime.utcnow()
                    )
                    
                    # Инициализируем первый снэпшот просмотров
                    if apt.views_total is not None:
                        apt.previous_views_total = apt.views_total
                        apt.previous_views_date = datetime.utcnow()
                        
                else:
                    # Обновляем существующую запись
                    old_views_total = apt.views_total
                    old_last_update = apt.updated_at
                    
                    apt.price = merged_data["price"]
                    apt.price_sqm = price_sqm
                    apt.floor = merged_data["floor"]
                    apt.max_floor = merged_data["max_floor"]
                    apt.address = merged_data["address"]
                    apt.description = merged_data.get("description", apt.description)
                    apt.image_url = merged_data.get("image_url", apt.image_url)
                    
                    # Обновляем детальные параметры только если они пришли из парсинга деталей
                    if merged_data.get("is_detailed_parsed"):
                        apt.title = merged_data.get("title", apt.title)
                        apt.image_urls = merged_data.get("image_urls", apt.image_urls)
                        apt.living_space = merged_data.get("living_space", apt.living_space)
                        apt.kitchen_space = merged_data.get("kitchen_space", apt.kitchen_space)
                        apt.house_material = merged_data.get("house_material", apt.house_material)
                        apt.year_built = merged_data.get("year_built", apt.year_built)
                        apt.ceiling_height = merged_data.get("ceiling_height", apt.ceiling_height)
                        apt.bathroom_type = merged_data.get("bathroom_type", apt.bathroom_type)
                        apt.balcony = merged_data.get("balcony", apt.balcony)
                        apt.window_view = merged_data.get("window_view", apt.window_view)
                        apt.repair = merged_data.get("repair", apt.repair)
                        apt.furniture = merged_data.get("furniture", apt.furniture)
                        apt.metro_name = merged_data.get("metro_name", apt.metro_name)
                        apt.metro_distance_minutes = merged_data.get("metro_distance_minutes", apt.metro_distance_minutes)
                        apt.metro_transport_type = merged_data.get("metro_transport_type", apt.metro_transport_type)
                        apt.parking = merged_data.get("parking", apt.parking)
                        apt.elevator = merged_data.get("elevator", apt.elevator)
                        apt.seller_name = merged_data.get("seller_name", apt.seller_name)
                        apt.seller_type = merged_data.get("seller_type", apt.seller_type)
                        apt.views_today = merged_data.get("views_today", apt.views_today)
                        apt.views_total = merged_data.get("views_total", apt.views_total)
                        apt.published_date = merged_data.get("published_date", apt.published_date)
                        apt.views_history_json = merged_data.get("views_history_json", apt.views_history_json)
                        apt.is_studio = merged_data.get("is_studio", apt.is_studio)
                        apt.is_apartment = merged_data.get("is_apartment", apt.is_apartment)
                        apt.is_auction = merged_data.get("is_auction", apt.is_auction)
                        apt.is_deposit_paid = merged_data.get("is_deposit_paid", apt.is_deposit_paid)
                        apt.is_alternative = merged_data.get("is_alternative", apt.is_alternative)
                        apt.is_share = merged_data.get("is_share", apt.is_share)
                        apt.is_paid_promotion = merged_data.get("is_paid_promotion", apt.is_paid_promotion)
                        apt.promotion_type = merged_data.get("promotion_type", apt.promotion_type)
                        apt.okrug = merged_data.get("okrug", apt.okrug)
                        apt.district = merged_data.get("district", apt.district)
                        apt.is_detailed_parsed = True
                        
                        # Обновляем снэпшот просмотров
                        update_views_snapshot(apt, old_views_total, old_last_update)
                        
                    apt.updated_at = datetime.utcnow()
                
                # Генерируем семантические теги
                apt.semantic_tags = generate_semantic_tags(apt)

                session.add(apt)
                parsed_count += 1
                
                # Делаем коммит каждые 5 квартир, чтобы не терять прогресс при падениях
                if parsed_count % 5 == 0:
                    await session.commit()

            await session.commit()

            # Шаг 3: Пересчет оценок скоринга для всех квартир
            all_stmt = select(Apartment)
            all_res = await session.exec(all_stmt)
            all_apts = list(all_res.all())

            if all_apts:
                updated_apts = recalculate_scores(all_apts, config)
                for u_apt in updated_apts:
                    session.add(u_apt)
                await session.commit()

        success_msg = (
            f"✅ Глубокий парсинг завершён.\n"
            f"Новых/обновлённых: {parsed_count}, отфильтровано: {skipped_count}\n"
            f"Детально обработано страниц за сессию: {detailed_scrapes_count}\n"
            f"Итого в базе: {len(all_apts)} объявлений"
        )
        logger.info(success_msg)
        await send_telegram_alert(success_msg)

    except Exception as e:
        err_msg = f"Критическая ошибка глубокого парсера: {e}"
        logger.exception(err_msg)
        await send_telegram_alert(err_msg)

    finally:
        if browser:
            await browser.close()
        if playwright_inst:
            await playwright_inst.stop()
