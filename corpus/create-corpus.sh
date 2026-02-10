#!/bin/bash

# create-corpus.sh
# Автоматически создаёт корпуса для тестирования перплексии

set -e

echo "========================================="
echo "Создание корпусов для тестирования перплексии"
echo "========================================="

# Конфигурация - ВСЕ ПУТИ ОТНОСИТЕЛЬНО ТЕКУЩЕЙ ДИРЕКТОРИИ
WORK_DIR="./corpus_temp"
LEAN_CORPUS="./lean_corpus.txt"
PYTHON_CORPUS="./python_corpus.txt"
OUTPUT_DIR="$(pwd)"  # Сохраняем абсолютный путь к текущей директории

# Создаём рабочую директорию
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "Рабочая директория: $(pwd)"
echo "Выходные файлы будут созданы в: $OUTPUT_DIR"

# Функция для клонирования репозитория
clone_repo() {
    local repo_url="$1"
    local repo_name="$2"
    
    echo "Клонируем $repo_name..."
    if [ -d "$repo_name" ]; then
        echo "  Репозиторий уже существует, обновляем..."
        cd "$repo_name"
        git pull --quiet
        cd ..
    else
        git clone --depth 1 --quiet "$repo_url" "$repo_name"
    fi
}

# Функция для сборки корпуса (ИСПРАВЛЕН ПУТЬ)
build_corpus() {
    local pattern="$1"
    local output_file="$2"
    
    echo "  Ищем файлы по шаблону: $pattern"
    find . -name "$pattern" -type f | while read -r file; do
        echo "    Добавляем: $file"
        # Используем абсолютный путь к выходному файлу
        cat "$file" >> "$OUTPUT_DIR/$output_file"
        echo "" >> "$OUTPUT_DIR/$output_file"  # Пустая строка между файлами
    done
}

# 1. СОЗДАЁМ LEAN-КОРПУС (mathlib4)
echo ""
echo "1. Создаём Lean-корпус из mathlib4..."
# Очищаем предыдущие файлы (если есть)
rm -f "$OUTPUT_DIR/$LEAN_CORPUS"

clone_repo "https://github.com/leanprover-community/mathlib4.git" "mathlib4"

echo "  Объединяем .lean файлы..."
cd mathlib4
build_corpus "*.lean" "$LEAN_CORPUS"
cd ..

LEAN_SIZE=$(wc -l < "$OUTPUT_DIR/$LEAN_CORPUS" 2>/dev/null || echo "0")
echo "  Готово! Строк в lean_corpus.txt: $LEAN_SIZE"

# 2. СОЗДАЁМ PYTHON-КОРПУС (Django + pandas)
echo ""
echo "2. Создаём Python-корпус..."
rm -f "$OUTPUT_DIR/$PYTHON_CORPUS"

# Клонируем Django
clone_repo "https://github.com/django/django.git" "django"
echo "  Добавляем Django..."
cd django
build_corpus "*.py" "$PYTHON_CORPUS"
cd ..

# Клонируем pandas
clone_repo "https://github.com/pandas-dev/pandas.git" "pandas"
echo "  Добавляем pandas..."
cd pandas
build_corpus "*.py" "$PYTHON_CORPUS"
cd ..

PYTHON_SIZE=$(wc -l < "$OUTPUT_DIR/$PYTHON_CORPUS" 2>/dev/null || echo "0")
echo "  Готово! Строк в python_corpus.txt: $PYTHON_SIZE"

# 3. ПОДРЕЗАЕМ РАЗМЕР КОРПУСОВ ДО 15M
head -c 15M lean_corpus.txt > lean_corpus.txt.tmp && mv lean_corpus.txt.tmp lean_corpus.txt
head -c 15M python_corpus.txt > python_corpus.txt.tmp && mv python_corpus.txt.tmp python_corpus.txt

# 4. ФИНАЛЬНАЯ ИНФОРМАЦИЯ
echo ""
echo "========================================="
echo "Создание корпусов завершено!"
echo "========================================="
echo "Созданные файлы:"
echo "  • $OUTPUT_DIR/$LEAN_CORPUS ($LEAN_SIZE строк)"
echo "  • $OUTPUT_DIR/$PYTHON_CORPUS ($PYTHON_SIZE строк)"
echo ""
echo "Для проверки размера в токенах:"
echo "  ./llama-cli -m ваша_модель.gguf -f $LEAN_CORPUS --perplexity 2>&1 | grep 'tokenization took'"
echo ""
echo "Для запуска теста перплексии:"
echo "  ./llama-cli -m ваша_модель.gguf -f $LEAN_CORPUS --perplexity -c 131072"
echo "========================================="
