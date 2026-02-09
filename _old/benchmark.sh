#!/usr/bin/env bash
# =================================================================
# СКРИПТ ТЕСТИРОВАНИЯ LLM МОДЕЛЕЙ (СТАБИЛЬНАЯ ВЕРСИЯ)
# =================================================================

set -e  # Выход при первой ошибке
export LC_ALL=C.UTF-8

# ==================== КОНФИГУРАЦИЯ ==============================
BIN_DIR="/app"
MODEL_DIR="/models"
CORPUS_DIR="/corpus"
RESULTS_DIR="/results"
mkdir -p "${RESULTS_DIR}"

# ==================== ДИАГНОСТИКА СИСТЕМЫ =======================
echo "🖥  ДИАГНОСТИКА СИСТЕМЫ"
echo "Хост: $(hostname)"
echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
echo "Память: $(grep 'MemTotal' /proc/meminfo | awk '{print $2/1024/1024 " GB"}')"
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader

# ==================== ФИКСИРОВАННЫЕ ПАРАМЕТРЫ ===================
# РУЧНАЯ НАСТРОЙКА ПОД ТВОЮ СИСТЕМУ (МЕНЯЙ ЗДЕСЬ)
CTX=16384
BATCH=512
THREADS=10

# Эвристика для NGL на основе имени модели
get_ngl_for_model() {
    local model=$1
    local model_lower=$(echo "$model" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$model_lower" == *"70b"* ]]; then
        echo "45"  # Для 70B моделей на 24 ГБ VRAM
    elif [[ "$model_lower" == *"32b"* ]] || [[ "$model_lower" == *"33b"* ]]; then
        echo "75"  # Для 32B/33B моделей
    else
        echo "99"  # Для всех остальных (почти все слои на GPU)
    fi
}

# ==================== ФУНКЦИИ ТЕСТИРОВАНИЯ ======================
run_benchmark() {
    local model=$1
    local ngl=$2
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="${RESULTS_DIR}/bench_${model}_${timestamp}.log"
    
    echo "🧪 ТЕСТ СКОРОСТИ: $model (NGL=$ngl)"
    
    # Запускаем llama-bench с безопасными параметрами
    timeout 300 "${BIN_DIR}/llama-bench" \
        -m "${MODEL_DIR}/${model}" \
        -c ${CTX} \
        -n 256 \
        -ngl ${ngl} \
        -t ${THREADS} \
        -fa \
        --verbose 2>&1 | tee "$log_file" || {
            echo "⚠️  Бенчмарк завершился с ошибкой или таймаутом"
            return 1
        }
    
    # Простая проверка успешности
    if tail -5 "$log_file" | grep -q "t/s"; then
        echo "✅ Бенчмарк завершён"
    else
        echo "❌ Возможная ошибка в бенчмарке"
        return 1
    fi
}

run_perplexity() {
    local model=$1
    local ngl=$2
    local corpus=$3
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local corpus_name=$(basename "$corpus" .txt)
    local log_file="${RESULTS_DIR}/ppl_${model}_${corpus_name}_${timestamp}.log"
    
    echo "📚 PERPLEXITY: $model → $corpus_name"
    
    # Используем --chunks 0 для быстрого теста (полный расчёт)
    timeout 600 "${BIN_DIR}/llama-perplexity" \
        -m "${MODEL_DIR}/${model}" \
        -f "$corpus" \
        -c ${CTX} \
        -ngl ${ngl} \
        -t ${THREADS} \
        -fa \
        --chunks 0 \
        --verbose 2>&1 | tee "$log_file" || {
            echo "⚠️  Perplexity тест завершился с ошибкой или таймаутом"
            return 1
        }
    
    # Извлекаем результат
    if grep -q "Final estimate:" "$log_file"; then
        local ppl=$(grep "Final estimate:" "$log_file" | tail -1 | grep -o "PPL = [0-9.]*" | cut -d' ' -f3)
        echo "🎯 PPL: ${ppl:-не найден}"
    else
        echo "⚠️  Не удалось получить PPL"
    fi
}

# ==================== ОСНОВНОЙ ЦИКЛ =============================
main() {
    # СПИСОК МОДЕЛЕЙ (оставь только те, которые есть в папке /models)
    local models=()
    
    # Автоматически находим все .gguf файлы
    for model_file in "$MODEL_DIR"/*.gguf; do
        if [[ -f "$model_file" ]]; then
            models+=("$(basename "$model_file")")
        fi
    done
    
    if [[ ${#models[@]} -eq 0 ]]; then
        echo "❌ Нет моделей в $MODEL_DIR"
        exit 1
    fi
    
    echo "📋 Найдено моделей: ${#models[@]}"
    
    # Корпусы для тестирования
    local corpora=("${CORPUS_DIR}/lean_corpus.txt" "${CORPUS_DIR}/python_corpus.txt")
    
    for model in "${models[@]}"; do
        echo ""
        echo "🚀 МОДЕЛЬ: $model"
        echo "========================================"
        
        # Определяем NGL для этой модели
        local ngl=$(get_ngl_for_model "$model")
        echo "⚙️  Параметры: CTX=${CTX}, NGL=${ngl}, THREADS=${THREADS}"
        
        # Тест скорости
        if ! run_benchmark "$model" "$ngl"; then
            echo "⏭️  Пропускаю остальные тесты для этой модели"
            continue
        fi
        
        # Тесты perplexity для каждого корпуса
        for corpus in "${corpora[@]}"; do
            if [[ -f "$corpus" ]]; then
                run_perplexity "$model" "$ngl" "$corpus"
            fi
        done
        
        echo "❄️  Пауза 30 сек..."
        sleep 30
    done
    
    echo ""
    echo "🎉 ТЕСТИРОВАНИЕ ЗАВЕРШЕНО"
    echo "📁 Логи в: $RESULTS_DIR"
}

# ==================== ЗАПУСК ====================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
