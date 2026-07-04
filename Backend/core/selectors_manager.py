import json
import os
import logging

logger = logging.getLogger("chianparser.selectors_manager")


class SelectorsManager:
    _instance = None
    _config = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(SelectorsManager, cls).__new__(cls, *args, **kwargs)
        return cls._instance

    def __init__(self):
        if self._config is not None:
            return
        self.reload_config()

    def reload_config(self):
        current_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.join(current_dir, "selectors_config.json")

        if not os.path.exists(config_path):
            logger.warning(
                "⚠️ selectors_config.json not found, using hardcoded fallback config"
            )
            self._config = self._get_fallback_config()
            return

        try:
            with open(config_path, "r", encoding="utf-8") as f:
                self._config = json.load(f)
            logger.info(
                "✅ Successfully loaded HTML/CSS selectors from selectors_config.json"
            )
        except Exception as e:
            logger.error(
                f"❌ Failed to decode selectors_config.json: {e}. Falling back to defaults."
            )
            self._config = self._get_fallback_config()

    @property
    def config(self) -> dict:
        if self._config is None:
            self.reload_config()
        return self._config

    def _get_fallback_config(self) -> dict:
        return {
            "search": {
                "cardSelector": "article",
                "linkSelector": "a[href]",
                "linkPattern": "/flat/",
                "titleKeys": ["TitleComponent", "OfferTitle"],
                "priceKeys": ["MainPrice", "ContentRow"],
                "geoKeys": ["GeoLabel"],
                "metroKeys": ["SpecialGeo"],
            },
            "detail": {
                "jsonSelectors": [
                    "script#__NEXT_DATA__",
                    "script[type='application/json']",
                    "script[id*='__']",
                    "script:containsData(offerData)",
                    "script:containsData(cianAd)",
                ],
                "mainCharacteristicsSelectors": [
                    "[data-name='OfferSummaryInfoItem']",
                    "[data-testid='object-summary-info-item']",
                    ".a10a3f92e9--item--_ipjK",
                    "[class*='item']",
                ],
                "mainCharacteristicsTitleSelector": "[data-mark='OfferSummaryInfoItem/Title']",
                "mainCharacteristicsValueSelector": "[data-mark='OfferSummaryInfoItem/Value']",
                "alternativeCharacteristicsSelectors": "[data-name='GeneralInformation'] li, [data-name='AboutFlatItem'], .object_descr_params li",
                "descriptionSelectors": [
                    "[data-name='Description']",
                    "[itemprop='description']",
                    ".description_text",
                    "[class*='description']",
                ],
                "addressSelectors": [
                    "[data-name='Geo']",
                    "[itemprop='address']",
                    "[class*='address']",
                    "h1[itemprop='name']",
                ],
                "metroSelectors": [
                    "[data-name='UndergroundStation']",
                    "[class*='underground']",
                    "[class*='metro']",
                    "a[href*='metro']",
                ],
                "sellerSelectors": [
                    "[data-automation='agent-info']",
                    "[data-automation='seller-info']",
                    "[class*='--agent-info--']",
                    "[class*='--owner-info--']",
                ],
            },
        }


selectors_manager = SelectorsManager()
