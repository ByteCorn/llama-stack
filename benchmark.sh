#!/usr/bin/env bash
# =================================================================
# СКРИПТ ДЛЯ ТЕСТИРОВАНИЯ LLM МОДЕЛЕЙ С АДАПТАЦИЕЙ ПОД РЕСУРСЫ
# =================================================================

set -eo pipefail
export LC_ALL=C.UTF-8

# ==================== КОНФИГУРАЦИЯ ==============================
readonly BIN_DIR="/app"
readonly MODEL_DIR="/models"
readonly CORPUS_DIR="/corpus"
readonly RESULTS_DIR="/results"
readonly CACHE_DIR="/cache"

mkdir -p "${RESULTS_DIR}" "${CACHE_DIR}"

# ==================== ДИАГНОСТИКА СИСТЕМЫ =======================
echo "🖥  ДИАГНОСТИКА СИСТЕМЫ"
echo "Хост: $(hostname)"
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "Память: $(free -h | awk '/^Mem:/ {print $2}')"
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader)
GPU_MEMORY_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
echo "GPU: ${GPU_NAME} (${GPU_MEMORY_MB} MB)"
echo "Модели: $(find "${MODEL_DIR}" -name '*.gguf' | wc -l) файлов"

# ==================== АДАПТИВНЫЕ ПАРАМЕТРЫ ======================
HOST_THREADS=$(nproc)
OPTIMAL_THREADS=$((HOST_THREADS - 2))
echo "Используем потоков CPU: ${OPTIMAL_THREADS}"

GPU_FREE_MB=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)
echo "Свободно памяти GPU: ${GPU_FREE_MB} MB"

if [[ ${GPU_FREE_MB} -gt 30000 ]]; then
    CTX=32768
    NGL="auto"
elif [[ ${GPU_FREE_MB} -gt 20000 ]]; then
    CTX=16384
    NGL="auto"
else
    CTX=8192
    NGL="auto"
fi

# Безопасная адаптация NGL для больших моделей (70B) по имени файла
model_name_lower=$(echo "${model}" | tr '[:upper:]' '[:lower:]')
if [[ "${model_name_lower}" == *"70b"* ]]; then
    echo "⚠️  Обнаружена 70B модель. Ограничиваю NGL."
    NGL=40  # Безопасное значение для 24 ГБ VRAM
fi

echo "Выбран размер контекста: ${CTX}"
echo "Выбран режим загрузки слоёв на GPU: ${NGL}"

# ==================== ФУНКЦИИ ТЕСТИРОВАНИЯ ======================
check_model() {
    local model=$1
    local model_path="${MODEL_DIR}/${model}"
    
    if ! "${BIN_DIR}/llama-inspect" -m "${model_path}" > /dev/null 2>&1; then
        echo "❌ Модель повреждена или несовместима: ${model}"
        return 1
    fi
    return 0
}

run_benchmark() {
    local model=$1
    local output="${RESULTS_DIR}/benchmark_${model}_$(date +%Y%m%d_%H%M%S).log"
    
    echo "🧪 ЗАПУСК БЕНЧМАРКА СКОРОСТИ ДЛЯ МОДЕЛИ: ${model}"
    
    # Запускаем llama-bench. Используем tee для записи лога.
    "${BIN_DIR}/llama-bench" \
        -m "${MODEL_DIR}/${model}" \
        -c ${CTX} \
        -n 256 \
        -ngl ${NGL} \
        -fa 2>&1 | tee "${output}"
    
    # Простой анализ результата (извлекаем последнюю строку таблицы)
    if tail -n 5 "${output}" | grep -q "t/s"; then
        echo "📈 Бенчмарк завершён. Полные результаты в: ${output}"
    else
        echo "⚠️  Возможная ошибка выполнения бенчмарка. Проверь лог: ${output}"
    fi
}

run_perplexity() {
    local model=$1
    local corpus=$2
    local output="${RESULTS_DIR}/perplexity_${model}_$(basename "${corpus}")_$(date +%Y%m%d_%H%M%S).log"
    
    echo "📚 ИЗМЕРЕНИЕ PERPLEXITY НА ФАЙЛЕ: $(basename "${corpus}")"
    
    # Используем --verbose для более детального вывода, tee записывает всё в лог.
    "${BIN_DIR}/llama-perplexity" \
        -m "${MODEL_DIR}/${model}" \
        -f "${corpus}" \
        -c ${CTX} \
        -ngl ${NGL} \
        -fa \
        --verbose 2>&1 | tee "${output}"
    
    # Универсальный способ извлечь итоговый PPL
    local final_ppl=$(grep -o "PPL = [0-9.]*" "${output}" | tail -1 | awk '{print $3}')
    if [[ -n "${final_ppl}" ]]; then
        echo "🎯 Итоговый PPL: ${final_ppl} (полный лог: ${output})"
    else
        echo "⚠️  Не удалось извлечь значение perplexity. Смотри лог: ${output}"
    fi
}

# ==================== ОСНОВНОЙ ЦИКЛ =============================
main() {
    declare -a MODELS=(
        "qwen2.5-coder-32b-instruct-q5_k_m.gguf"
        "Qwen2.5-Coder-32B-Instruct-abliterated-Q5_K_M.gguf"
        "Llama-3.3-70B-Instruct-abliterated-Q3_K_M.gguf"
    )
    
    # Важно: имя массива CORPUS, а не CORPORA!
    declare -a CORPUS=(
        "${CORPUS_DIR}/lean_corpus.txt"
        "${CORPUS_DIR}/python_corpus.txt"
    )
    
    for model in "${MODELS[@]}"; do
        if [[ ! -f "${MODEL_DIR}/${model}" ]]; then
            echo "⚠️ Файл модели не найден: ${model}. Пропускаю."
            continue
        fi

        echo ""
        echo "🚀 НАЧИНАЮ ТЕСТИРОВАНИЕ МОДЕЛИ: ${model}"
        echo "========================================"
        
        if ! check_model "${model}"; then
            continue
        fi
        
        run_benchmark "${model}"
        
        # Критичное исправление: используем правильное имя массива CORPUS
        for corpus in "${CORPUS[@]}"; do
            if [[ -f "${corpus}" ]]; then
                run_perplexity "${model}" "${corpus}"
            else
                echo "⚠️ Файл корпуса не найден: ${corpus}"
            fi
        done
        
        echo "❄️ Пауза для охлаждения GPU (30 сек)..."
        sleep 30
    done
    
    echo ""
    echo "🎉 ТЕСТИРОВАНИЕ ЗАВЕРШЕНО"
    echo "📊 Результаты и полные логи в: ${RESULTS_DIR}"
}

# ==================== ЗАПУСК ====================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
