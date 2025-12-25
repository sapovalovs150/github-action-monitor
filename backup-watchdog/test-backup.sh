#!/bin/bash
# test-backup.sh - Тестирование скрипта backup-watchdog.sh

# Создаем тестовую папку если её нет
TEST_DIR="./test_folder"
if [ ! -d "$TEST_DIR" ]; then
    mkdir -p "$TEST_DIR"
    echo "✅ Создана тестовая папка: $TEST_DIR"
fi

# Создаем несколько тестовых файлов
echo "Создаю тестовые файлы..."
echo "Это тестовый файл 1" > "$TEST_DIR/file1.txt"
echo "Это тестовый файл 2" > "$TEST_DIR/file2.txt"
mkdir -p "$TEST_DIR/test_folder"
echo "Файл внутри папки" > "$TEST_DIR/test_folder/inner.txt"

echo "✅ Тестовые файлы созданы:"
ls -la "$TEST_DIR"

echo ""
echo "Для проверки работы:"
echo "1. Откройте новое окно Git Bash"
echo "2. Перейдите в эту же папку: cd $(pwd)"
echo "3. Запустите мониторинг: ./backup-watchdog.sh '$TEST_DIR'"
echo "4. В этом окне добавляйте файлы в папку $TEST_DIR"
echo ""
echo "Или запустите этот скрипт снова для создания новых тестовых файлов."