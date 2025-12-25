#!/bin/bash
# test-monitor.sh - Локальный тест мониторинга папки

TARGET_FOLDER="${1:-src}"
FOLDER_SIZE_LIMIT_MB=50
FILE_COUNT_LIMIT=100
FOLDER_COUNT_LIMIT=20

echo "=== 🧪 ЛОКАЛЬНЫЙ ТЕСТ МОНИТОРИНГА ==="
echo "Папка для мониторинга: $TARGET_FOLDER"
echo ""

# Проверка существования папки
if [ ! -d "$TARGET_FOLDER" ]; then
    echo "❌ Папка '$TARGET_FOLDER' не существует"
    echo "Создайте папку или укажите другую: ./test-monitor.sh folder_name"
    exit 1
fi

# Рассчёт статистики
echo "=== 📊 РАСЧЁТ СТАТИСТИКИ ==="
FOLDER_SIZE_MB=$(du -sm "$TARGET_FOLDER" 2>/dev/null | cut -f1 || echo "0")
FILE_COUNT=$(find "$TARGET_FOLDER" -type f 2>/dev/null | wc -l || echo "0")
FOLDER_COUNT=$(find "$TARGET_FOLDER" -type d 2>/dev/null | tail -n +2 | wc -l || echo "0")

echo "Размер папки: ${FOLDER_SIZE_MB} MB"
echo "Количество файлов: ${FILE_COUNT}"
echo "Количество папок: ${FOLDER_COUNT}"
echo ""

# Проверка лимитов
echo "=== ⚠️  ПРОВЕРКА ЛИМИТОВ ==="
FAILED=0

if [ "$FOLDER_SIZE_MB" -gt "$FOLDER_SIZE_LIMIT_MB" ]; then
    echo "❌ ПРЕВЫШЕН ЛИМИТ РАЗМЕРА: ${FOLDER_SIZE_MB} MB > ${FOLDER_SIZE_LIMIT_MB} MB"
    FAILED=1
else
    echo "✅ Размер в пределах: ${FOLDER_SIZE_MB} MB ≤ ${FOLDER_SIZE_LIMIT_MB} MB"
fi

if [ "$FILE_COUNT" -gt "$FILE_COUNT_LIMIT" ]; then
    echo "❌ ПРЕВЫШЕН ЛИМИТ ФАЙЛОВ: ${FILE_COUNT} > ${FILE_COUNT_LIMIT}"
    FAILED=1
else
    echo "✅ Файлов в пределах: ${FILE_COUNT} ≤ ${FILE_COUNT_LIMIT}"
fi

if [ "$FOLDER_COUNT" -gt "$FOLDER_COUNT_LIMIT" ]; then
    echo "❌ ПРЕВЫШЕН ЛИМИТ ПАПОК: ${FOLDER_COUNT} > ${FOLDER_COUNT_LIMIT}"
    FAILED=1
else
    echo "✅ Папок в пределах: ${FOLDER_COUNT} ≤ ${FOLDER_COUNT_LIMIT}"
fi

echo ""
echo "=== 🎯 ИТОГ ==="
if [ "$FAILED" -eq 1 ]; then
    echo "❌ Обнаружено превышение лимитов!"
    echo "Рекомендуется:"
    echo "1. Удалить ненужные файлы из '$TARGET_FOLDER'"
    echo "2. Увеличить лимиты в файле workflow"
    echo "3. Оптимизировать структуру проекта"
    exit 1
else
    echo "✅ Все проверки пройдены!"
    echo "Статистика в норме."
fi