from datetime import datetime, timezone

from fastapi import APIRouter
from fastapi.responses import Response

router = APIRouter(tags=["appcast"])

_RELEASE_VERSION = "1.1.0"
_BUILD_NUMBER = "2"
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
                length="20525682"
                type="application/octet-stream"
                sparkle:edSignature="f+FY61qNHyMHYmcjlnAwm+U6A90g0BB1HIVFay/bRCvxUQfHIa1oV8v84QoKJcnntjJmd0eT/hWwn1KyL74BAg=="
            />
        </item>
    </channel>
</rss>"""


@router.get("/updates/appcast.xml")
async def get_appcast() -> Response:
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    xml = _APPCAST_TEMPLATE.format(
        base_url=_BASE_URL,
        build=_BUILD_NUMBER,
        short_version=_RELEASE_VERSION,
        pub_date=pub_date,
    )
    return Response(content=xml, media_type="application/xml")


from fastapi.responses import FileResponse
import os

@router.get("/updates/download/latest.dmg")
async def download_latest() -> FileResponse:
    file_path = "updates/ChianParser_1.1.0_b2.dmg"
    return FileResponse(
        path=file_path,
        media_type="application/octet-stream",
        filename="ChianParser-1.0.1.dmg"
    )
