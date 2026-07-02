#!/bin/bash
# Скрипт резервного копирования базы данных ChianParser и отправки в S3
# Все комментарии на русском языке

set -e

# Настройки бэкапа
BACKUP_DIR="/tmp/chianparser_backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DATABASE_NAME="chianparser"
BACKUP_FILE="${BACKUP_DIR}/${DATABASE_NAME}_backup_${TIMESTAMP}.sql"
S3_BUCKET="${S3_BUCKET_NAME:-chianparser-backups}"

# Создаем папку для бэкапов, если её нет
mkdir -p "$BACKUP_DIR"

echo "[$(date)] Начало резервного копирования базы данных ${DATABASE_NAME}..."

# Выполняем дамп базы данных
if [ -n "$DATABASE_URL" ]; then
  # Если передан DATABASE_URL, используем его для дампа
  pg_dump "$DATABASE_URL" -F c -f "$BACKUP_FILE"
else
  # Иначе используем стандартное подключение к localhost
  pg_dump -U postgres -h localhost -d "$DATABASE_NAME" -F c -f "$BACKUP_FILE"
fi

echo "[$(date)] Дамп базы данных успешно создан: ${BACKUP_FILE}"

# Загружаем дамп в S3
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "[$(date)] Загрузка бэкапа в S3 бакет s3://${S3_BUCKET}..."
  
  ENDPOINT_ARG=""
  if [ -n "$S3_ENDPOINT_URL" ]; then
    ENDPOINT_ARG="--endpoint-url ${S3_ENDPOINT_URL}"
  fi
  
  # Загружаем файл с помощью AWS CLI
  aws s3 cp "$BACKUP_FILE" "s3://${S3_BUCKET}/backups/$(basename "$BACKUP_FILE")" $ENDPOINT_ARG
  
  echo "[$(date)] Бэкап успешно загружен в S3"
else
  echo "[$(date)] Предупреждение: Переменные AWS_ACCESS_KEY_ID и AWS_SECRET_ACCESS_KEY не настроены. Загрузка в S3 пропущена."
fi

# Удаляем локальный файл бэкапа
rm -f "$BACKUP_FILE"
echo "[$(date)] Локальный файл бэкапа удален."
echo "[$(date)] Резервное копирование завершено успешно."
