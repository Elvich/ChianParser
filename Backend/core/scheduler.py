import logging
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from services.parser import run_stealth_parser

# Настройка логирования
logger = logging.getLogger("chianparser.scheduler")
logger.setLevel(logging.INFO)

scheduler = AsyncIOScheduler()


def start_scheduler() -> None:
    """
    Запускает планировщик фоновых задач.
    Настраивает запуск стелс-парсера 3 раза в день (в 9:00, 15:00 и 21:00).
    """
    logger.info("⏰ Инициализация планировщика задач...")

    # Добавляем задачу парсинга в 9:00, 15:00 и 21:00
    scheduler.add_job(
        run_stealth_parser,
        trigger=CronTrigger(hour="9,15,21", minute="0", second="0"),
        id="stealth_parser_job",
        replace_existing=True,
    )

    scheduler.start()
    logger.info("⏰ Планировщик фоновых задач успешно запущен")


def shutdown_scheduler() -> None:
    """
    Останавливает планировщик при выключении приложения.
    """
    logger.info("⏰ Остановка планировщика задач...")
    if scheduler.running:
        scheduler.shutdown()
        logger.info("⏰ Планировщик задач успешно остановлен")
