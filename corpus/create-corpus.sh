#!/bin/bash

# create-corpus.sh
# Автоматически создаёт корпуса для тестирования перплексии:
# 1. lean_corpus.txt - из математической библиотеки Lean 4 (mathlib4)
# 2. python_corpus.txt - из крупных Python-проектов (Django, pandas)

set -e  # Завершить скрипт при любой ошибке

echo "========================================="
echo "Создание корпусов для тестирования перплексии"
echo "========================================="

# Конфигурация
WORK_DIR="./corpus_temp"
LEAN_CORPUS="./lean_corpus.txt"
PYTHON_CORPUS="./python_corpus.txt"

# Создаём рабочую директорию
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "Рабочая директория: $(pwd)"

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

# Функция для сборки корпуса
build_corpus() {
    local pattern="$1"
    local output_file="$2"
    
    echo "  Ищем файлы по шаблону: $pattern"
    find . -name "$pattern" -type f | while read -r file; do
        echo "    Добавляем: $file"
        cat "$file" >> "../$output_file"
        echo "" >> "../$output_file"  # Добавляем пустую строку между файлами
    done
}

# 1. СОЗДАЁМ LEAN-КОРПУС (mathlib4)
echo ""
echo "1. Создаём Lean-корпус из mathlib4..."
rm -f "../$LEAN_CORPUS"

clone_repo "https://github.com/leanprover-community/mathlib4.git" "mathlib4"

echo "  Объединяем .lean файлы..."
cd mathlib4
build_corpus "*.lean" "$LEAN_CORPUS"
cd ..

LEAN_SIZE=$(wc -l < "../$LEAN_CORPUS")
echo "  Готово! Строк в lean_corpus.txt: $LEAN_SIZE"

# 2. СОЗДАЁМ PYTHON-КОРПУС (Django + pandas)
echo ""
echo "2. Создаём Python-корпус..."
rm -f "../$PYTHON_CORPUS"

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

PYTHON_SIZE=$(wc -l < "../$PYTHON_CORPUS")
echo "  Готово! Строк в python_corpus.txt: $PYTHON_SIZE"

# 3. ФИНАЛЬНАЯ ИНФОРМАЦИЯ
echo ""
echo "========================================="
echo "Создание корпусов завершено!"
echo "========================================="
echo "Созданные файлы:"
echo "  • $LEAN_CORPUS ($LEAN_SIZE строк)"
echo "  • $PYTHON_CORPUS ($PYTHON_SIZE строк)"
echo ""
echo "Для проверки размера в токенах выполните:"
echo "  ./llama-cli -m ваша_модель.gguf -f lean_corpus.txt --perplexity 2>&1 | grep 'tokenization took'"
echo ""
echo "Для запуска теста перплексии:"
echo "  ./llama-cli -m ваша_модель.gguf -f lean_corpus.txt --perplexity -c 131072"
echo "========================================="
