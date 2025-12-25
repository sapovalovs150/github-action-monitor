#!/bin/bash
# backup-watchdog.sh - Мониторит папку и автоматически архивирует новые файлы/папки

# Пути к конфигурационным файлам (можно переопределить через переменные окружения)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${BACKUP_CONFIG:-$SCRIPT_DIR/backup-watchdog.conf}"
LOG_FILE="${BACKUP_LOG:-$SCRIPT_DIR/backup-watchdog.log}"

# Значения по умолчанию (будут перезаписаны конфигом если он существует)
CHECK_INTERVAL=5                  # Интервал проверки в секундах
MAX_LOG_SIZE=10485760             # Максимальный размер лог-файла (10 MB)
ENABLE_LOGGING=true               # Включить логирование в файл
ARCHIVE_PREFIX="backup"           # Префикс для архивов
KEEP_ORIGINAL=false               # Не удалять оригиналы после архивации (тестовый режим)

# Функция логирования
log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    
    # Проверяем доступность команды date (на случай минимальных окружений)
    if command -v date >/dev/null 2>&1; then
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    else
        timestamp="[NO-DATE]"
    fi
    
    # Формируем строку лога
    local log_entry="[$timestamp] [$level] $message"
    
    # Вывод в консоль с цветами
    case "$level" in
        "ERROR")
            echo -e "\033[0;31m$log_entry\033[0m"  # Красный
            ;;
        "WARN")
            echo -e "\033[1;33m$log_entry\033[0m"  # Жёлтый
            ;;
        "INFO")
            echo -e "\033[0;32m$log_entry\033[0m"  # Зелёный
            ;;
        "DEBUG")
            echo -e "\033[0;34m$log_entry\033[0m"  # Синий
            ;;
        *)
            echo -e "\033[0;37m$log_entry\033[0m"  # Белый
            ;;
    esac
    
    # Запись в лог-файл (если включено)
    if [ "$ENABLE_LOGGING" = true ] && [ -n "$LOG_FILE" ]; then
        # Проверяем размер лог-файла и ротируем если нужно
        if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
            mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null
            log_message "INFO" "Лог-файл превысил лимит, создан новый"
        fi
        echo "$log_entry" >> "$LOG_FILE"
    fi
}

# Функция безопасного получения имени файла (экранирование спецсимволов)
safe_filename() {
    echo "$1" | sed 's/[^a-zA-Z0-9._-]/_/g'
}

# Функция загрузки конфигурации
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_message "INFO" "Загружаю конфигурацию из $CONFIG_FILE"
        
        # Безопасная загрузка конфига
        while IFS='=' read -r key value; do
            # Пропускаем комментарии и пустые строки
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Убираем кавычки если есть
            value="${value%\"}"
            value="${value#\"}"
            
            case "$key" in
                "CHECK_INTERVAL")
                    if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ]; then
                        CHECK_INTERVAL="$value"
                    else
                        log_message "WARN" "Некорректный CHECK_INTERVAL: $value, использую значение по умолчанию: 5"
                    fi
                    ;;
                "ENABLE_LOGGING")
                    if [[ "$value" =~ ^(true|false)$ ]]; then
                        ENABLE_LOGGING="$value"
                    fi
                    ;;
                "ARCHIVE_PREFIX")
                    ARCHIVE_PREFIX="$value"
                    ;;
                "KEEP_ORIGINAL")
                    if [[ "$value" =~ ^(true|false)$ ]]; then
                        KEEP_ORIGINAL="$value"
                    fi
                    ;;
                "MAX_LOG_SIZE")
                    if [[ "$value" =~ ^[0-9]+$ ]]; then
                        MAX_LOG_SIZE="$value"
                    fi
                    ;;
                *)
                    log_message "DEBUG" "Неизвестный параметр конфига: $key"
                    ;;
            esac
        done < "$CONFIG_FILE"
        
        log_message "INFO" "Конфигурация загружена: interval=${CHECK_INTERVAL}s, logging=$ENABLE_LOGGING"
    else
        log_message "INFO" "Конфигурационный файл не найден, использую значения по умолчанию"
    fi
}

# Функция проверки зависимостей
check_dependencies() {
    local missing_deps=()
    
    # Проверяем tar
    if ! command -v tar >/dev/null 2>&1; then
        missing_deps+=("tar")
    fi
    
    # Проверяем sed (для safe_filename)
    if ! command -v sed >/dev/null 2>&1; then
        missing_deps+=("sed")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_message "ERROR" "Отсутствуют необходимые команды: ${missing_deps[*]}"
        log_message "INFO" "Установите их и попробуйте снова"
        return 1
    fi
    
    return 0
}

# Функция создания архива
create_archive() {
    local source_path="$1"
    local watch_dir="$2"
    local item_name="$3"
    
    # Безопасное имя для архива
    local safe_name=$(safe_filename "$item_name")
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local archive_name="${ARCHIVE_PREFIX}_${timestamp}_${safe_name}.tar.gz"
    local archive_path="${watch_dir}/${archive_name}"
    
    log_message "INFO" "Начинаю архивацию: $item_name"
    log_message "DEBUG" "Путь: $source_path"
    log_message "DEBUG" "Будет создан архив: $archive_name"
    
    # Создаём архив
    if tar -czf "$archive_path" -C "$watch_dir" "$item_name" 2>/dev/null; then
        # Проверяем что архив создан и не пустой
        if [ -f "$archive_path" ] && [ -s "$archive_path" ]; then
            log_message "INFO" "Архив успешно создан: $archive_name ($(du -h "$archive_path" | cut -f1))"
            
            # Удаляем оригинал если не включен тестовый режим
            if [ "$KEEP_ORIGINAL" = false ]; then
                if rm -rf "$source_path"; then
                    log_message "INFO" "Оригинал удалён: $item_name"
                else
                    log_message "WARN" "Не удалось удалить оригинал: $item_name"
                fi
            else
                log_message "INFO" "Тестовый режим: оригинал сохранён"
            fi
            return 0
        else
            log_message "ERROR" "Архив создан пустым или повреждён"
            rm -f "$archive_path" 2>/dev/null
            return 1
        fi
    else
        log_message "ERROR" "Ошибка при создании архива для: $item_name"
        return 1
    fi
}

# Функция проверки папки и архивации новых файлов
check_and_archive() {
    local watch_dir="$1"
    
    # Проверяем что папка всё ещё существует
    if [ ! -d "$watch_dir" ]; then
        log_message "ERROR" "Папка для мониторинга больше не существует: $watch_dir"
        return 1
    fi
    
    # Ищем файлы и папки в целевой директории
    local found_items=0
    local archived_items=0
    local failed_items=0
    
    for item_path in "$watch_dir"/*; do
        # Пропускаем если нет файлов
        [ -e "$item_path" ] || continue
        
        # Пропускаем архивные файлы .tar.gz
        [[ "$item_path" == *.tar.gz ]] && continue
        
        # Пропускаем наши служебные файлы
        local item_name=$(basename "$item_path")
        [[ "$item_name" == "backup-watchdog.log" ]] && continue
        [[ "$item_name" == "backup-watchdog.conf" ]] && continue
        [[ "$item_name" == backup_*.tar.gz ]] && continue
        
        found_items=$((found_items + 1))
        
        # Архивируем файл или папку
        if create_archive "$item_path" "$watch_dir" "$item_name"; then
            archived_items=$((archived_items + 1))
        else
            failed_items=$((failed_items + 1))
        fi
    done
    
    if [ $found_items -gt 0 ]; then
        log_message "INFO" "Проверка завершена: найдено $found_items, архивировано $archived_items, ошибок: $failed_items"
    fi
    
    return $failed_items
}

# Обработка аргументов командной строки
print_usage() {
    echo "Использование: $0 [ОПЦИИ] /путь/к/папке"
    echo ""
    echo "Опции:"
    echo "  -c, --config FILE    Использовать указанный конфигурационный файл"
    echo "  -l, --log FILE       Использовать указанный лог-файл"
    echo "  -i, --interval SEC   Интервал проверки в секундах"
    echo "  -t, --test           Тестовый режим (не удалять оригиналы)"
    echo "  -h, --help           Показать эту справку"
    echo ""
    echo "Примеры:"
    echo "  $0 ./test_folder"
    echo "  $0 -c ./my-config.conf -i 10 /path/to/watch"
    echo "  $0 --test --interval 30 /home/user/documents"
}

# Парсим аргументы
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -i|--interval)
            if [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -gt 0 ]; then
                CHECK_INTERVAL="$2"
            else
                echo "Ошибка: Интервал должен быть положительным числом" >&2
                exit 1
            fi
            shift 2
            ;;
        -t|--test)
            KEEP_ORIGINAL=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        -*)
            echo "Неизвестная опция: $1" >&2
            print_usage
            exit 1
            ;;
        *)
            WATCH_DIR="$1"
            shift
            ;;
    esac
done

# Проверяем, передан ли аргумент (путь к папке)
if [ -z "$WATCH_DIR" ]; then
    log_message "ERROR" "Не указана папка для отслеживания."
    print_usage
    exit 1
fi

# Проверяем, существует ли указанная папка
if [ ! -d "$WATCH_DIR" ]; then
    log_message "ERROR" "Папка '$WATCH_DIR' не существует."
    exit 1
fi

# Проверяем зависимости
if ! check_dependencies; then
    exit 1
fi

# Загружаем конфигурацию
load_config

# Получаем абсолютный путь к папке
WATCH_DIR=$(cd "$WATCH_DIR" && pwd)

# Запускаем мониторинг
log_message "INFO" "================================================"
log_message "INFO" "Запуск мониторинга папки: $WATCH_DIR"
log_message "INFO" "Конфигурационный файл: ${CONFIG_FILE:-не используется}"
log_message "INFO" "Лог-файл: ${LOG_FILE:-не используется}"
log_message "INFO" "Интервал проверки: ${CHECK_INTERVAL} секунд"
log_message "INFO" "Тестовый режим: ${KEEP_ORIGINAL}"
log_message "INFO" "Префикс архивов: ${ARCHIVE_PREFIX}"
log_message "INFO" "================================================"
log_message "INFO" "Для остановки нажмите Ctrl+C"
log_message "INFO" "---"

# Основной цикл мониторинга
while true; do
    check_and_archive "$WATCH_DIR"
    
    # Пауза перед следующей проверкой
    sleep "$CHECK_INTERVAL"
done
