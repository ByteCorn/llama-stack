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
nvidia-smi --query-gpu=name,memory.total,memory.free,memory.used,driver_version --format=csv

# ==================== ПОДБОР ПАРАМЕТРОВ =========================
# Используем контекст из Docker Compose. Если не задан, ставим безопасные 8192.
CTX="${LLAMA_ARG_CTX_SIZE:-8192}"
NGL="${LLAMA_ARG_N_GPU_LAYERS:-auto}"

# Потоки из переменных окружения или дефолт
THREADS="${LLAMA_ARG_THREADS:-10}"

# Эвристика для NGL на основе имени модели
get_ngl_for_model() {
    local model=$1

    # Установка NGL под 24GB VRAM
    if [[ $model == *"qwen2.5-coder-32b-instruct-q5_k_m"* ]]; then
        echo "63" # из 64 слоёв
    elif [[ $model == *"Qwen2.5-Coder-32B-Instruct-abliterated-Q5_K_M"* ]]; then
        echo "63" # из 64 слоёв
    elif [[ $model == *"Llama_3.x_70b_L3.3-Dolphin-Eva_fusion_v2.Q3_K_L"* ]]; then
        echo "49" # из 80 слоёв
    elif [[ $model == *"gpt-oss-20b-mxfp4.gguf"* ]]; then
        echo "99" # offloaded 50/81 layers
    else
       echo "30"  # Для всех остальных
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
    ${BIN_DIR}/llama-bench \
        -m "${MODEL_DIR}/${model}" \
        -p ${CTX} \
        -ngl ${ngl} \
        -t ${THREADS} \
        -fa auto \
        --verbose 2>&1 | tee "$log_file" || {
            echo "⚠️  Бенчмарк завершился с ошибкой или таймаутом"
            echo ""
            # Продолжаем тесты, несмотря на ошибку
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
    ${BIN_DIR}/llama-perplexity \
        -m "${MODEL_DIR}/${model}" \
        -f "$corpus" \
        -c ${CTX} \
        -ngl ${ngl} \
        -t ${THREADS} \
        -fa auto \
        --chunks 0 \
        --verbose 2>&1 | tee "$log_file" || {
            echo "⚠️  Perplexity тест завершился с ошибкой или таймаутом"
            echo ""
            # Продолжаем тесты, несмотря на ошибку
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
    # СПИСОК МОДЕЛЕЙ
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
