import pytest
from datetime import datetime
from services.parser import (
    find_value_recursive,
    extract_district,
    extract_okrug,
    parse_views_formatted_string,
    _parse_room_info,
    _parse_price,
    _parse_metro_distance
)

def test_find_value_recursive():
    data = {
        "a": 1,
        "nested": {
            "b": 2,
            "target": "found_me",
            "list": [
                {"c": 3},
                {"target": "found_deep"}
            ]
        }
    }
    assert find_value_recursive(data, "target") == "found_me"
    assert find_value_recursive(data, "b") == 2
    assert find_value_recursive(data, "c") == 3
    assert find_value_recursive(data, "non_existent") is None


def test_extract_district_and_okrug():
    address = "Москва, ЦАО, р-н Арбат, ул. Арбат, д. 1"
    assert extract_district(address) == "Арбат"
    assert extract_okrug(address) == "ЦАО"

    address_no_district = "Москва, Зеленоград, Зеленоградский административный округ"
    assert extract_district(address_no_district) is None
    assert extract_okrug(address_no_district) == "Зеленоград"

    address_by_mapping = "Москва, ул. Академика Королева, р-н Останкинский"
    assert extract_district(address_by_mapping) == "Останкинский"
    assert extract_okrug(address_by_mapping) == "СВАО"


def test_parse_views_formatted_string():
    # 1. С общим числом и числом за сегодня
    total, today = parse_views_formatted_string("1 450 просмотров, 12 за сегодня")
    assert total == 1450
    assert today == 12

    # 2. Тонкие и неразрывные пробелы
    total, today = parse_views_formatted_string("1\u00A0200\u202fпросмотров, 5\u00A0за сегодня")
    assert total == 1200
    assert today == 5

    # 3. Только за сегодня
    total, today = parse_views_formatted_string("7 за сегодня")
    assert total is None
    assert today == 7

    # 4. Некорректный формат
    total, today = parse_views_formatted_string("какой-то левый текст")
    assert total is None
    assert today is None

    # 5. С фразой "нет за сегодня"
    total, today = parse_views_formatted_string("1 450 просмотров, нет за сегодня")
    assert total == 1450
    assert today == 0

    # 6. Только "нет за сегодня"
    total, today = parse_views_formatted_string("нет за сегодня")
    assert total is None
    assert today == 0

    # 7. Без сегодняшних просмотров вообще
    total, today = parse_views_formatted_string("1 450 просмотров")
    assert total == 1450
    assert today is None



def test_parse_room_info():
    info = _parse_room_info("2-комн. апартаменты, 54,3 м², 3/10 этаж")
    assert info["rooms"] == 2
    assert info["space"] == 54.3
    assert info["floor"] == 3
    assert info["max_floor"] == 10
    assert info["is_studio"] is False
    assert info["is_apartment"] is True

    info_studio = "Студия, 22 м², 1/5 этаж"
    info = _parse_room_info(info_studio)
    assert info["rooms"] == 1
    assert info["space"] == 22.0
    assert info["floor"] == 1
    assert info["max_floor"] == 5
    assert info["is_studio"] is True
    assert info["is_apartment"] is False


def test_parse_price():
    assert _parse_price("15 000 000 ₽") == 15000000.0
    assert _parse_price("350\u00A0000\u202f₽/мес.") == 350000.0
    assert _parse_price("цена договорная") == 0.0


def test_parse_metro_distance():
    assert _parse_metro_distance("10 мин. пешком") == 10
    assert _parse_metro_distance("5 минут на транспорте") == 5
    assert _parse_metro_distance("близко к метро") == 0
