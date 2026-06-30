import json
import os
from datetime import datetime, timezone

from fastapi import APIRouter
from fastapi.responses import FileResponse, Response

router = APIRouter(tags=["appcast"])

_DEFAULT_RELEASE_VERSION = "1.1.0"
_DEFAULT_BUILD_NUMBER = "2"
_DEFAULT_LENGTH = "20525682"
_DEFAULT_SIGNATURE = "f+FY61qNHyMHYmcjlnAwm+U6A90g0BB1HIVFay/bRCvxUQfHIa1oV8v84QoKJcnntjJmd0eT/hWwn1KyL74BAg=="
_DEFAULT_DMG_NAME = "ChianParser_1.1.0_b2.dmg"
_BASE_URL = "https://flipping.elvi4.tech/api/v1/updates"

_APPCAST_TEMPLATE = """\
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>ChianParser Changelog</title>
        <link>{base_url}/appcast.xml</link>
        <description>Most recent updates to ChianParser</description>
        <language>en</language>
        <item>
            <title>Version {short_version}</title>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{short_version}</sparkle:shortVersionString>
            <description><![CDATA[
                <h2>What's new in {short_version}</h2>
                <ul>
                    <li>Integrated Local LLM (Gemma 4) for AI-powered apartment parsing</li>
                    <li>Added Anti-Sleep Power Management for long parsing tasks</li>
                    <li>Stability improvements and better UI with AI settings tab</li>
                </ul>
            ]]></description>
            <pubDate>{pub_date}</pubDate>
            <enclosure
                url="{base_url}/download/latest.dmg"
                sparkle:version="{build}"
                sparkle:shortVersionString="{short_version}"
                length="{length}"
                type="application/octet-stream"
                sparkle:edSignature="{signature}"
            />
        </item>
    </channel>
</rss>"""


def _load_latest_manifest() -> dict:
    manifest_path = "updates/latest.json"
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path, "r") as f:
                return json.load(f)
        except Exception as e:
            print(f"⚠️ Ошибка чтения latest.json: {e}")
    return {}


@router.get("/updates/appcast.xml")
async def get_appcast() -> Response:
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    manifest = _load_latest_manifest()

    build = manifest.get("build", _DEFAULT_BUILD_NUMBER)
    short_version = manifest.get("version", _DEFAULT_RELEASE_VERSION)
    length = manifest.get("length", _DEFAULT_LENGTH)
    signature = manifest.get("edSignature", _DEFAULT_SIGNATURE)

    xml = _APPCAST_TEMPLATE.format(
        base_url=_BASE_URL,
        build=build,
        short_version=short_version,
        pub_date=pub_date,
        length=length,
        signature=signature,
    )
    return Response(content=xml, media_type="application/xml")


@router.get("/updates/download/latest.dmg")
async def download_latest() -> FileResponse:
    manifest = _load_latest_manifest()
    dmg_name = manifest.get("dmg_name", _DEFAULT_DMG_NAME)
    file_path = os.path.join("updates", dmg_name)

    # Проверяем, существует ли кастомный файл, иначе отдаем дефолтный
    if not os.path.exists(file_path):
        file_path = os.path.join("updates", _DEFAULT_DMG_NAME)

    return FileResponse(
        path=file_path,
        media_type="application/octet-stream",
        filename="ChianParser.dmg",
    )
