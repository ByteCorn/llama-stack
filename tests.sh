#!/bin/bash

# Прямые пути к бинарникам
BENCH_BIN="/app/llama-bench"
PPL_BIN="/app/llama-perplexity"
MODEL_DIR="/models"
RESULTS_DIR="/results"

# Создаем директорию для результатов и даем права на запись
mkdir -p "${RESULTS_DIR}"
chmod 777 "${RESULTS_DIR}" 2>/dev/null || true

# Используем контекст из Docker Compose. Если не задан, ставим безопасные 8192.
CTX="${LLAMA_ARG_CTX_SIZE:-8192}"
DEFAULT_NGL="${LLAMA_ARG_N_GPU_LAYERS:-auto}"

# Потоки из переменных окружения или дефолт
THREADS="${LLAMA_ARG_THREADS:-10}"

# Список моделей
MODELS=(
  "qwen2.5-coder-32b-instruct-q5_k_m.gguf"
  "Qwen2.5-Coder-32B-Instruct-abliterated-Q5_K_M.gguf"
  "Llama_3.x_70b_L3.3-Dolphin-Eva_fusion_v2.Q3_K_L.gguf"
  "Llama-3.3-70B-Instruct-abliterated-Q3_K_M.gguf"
)

CORPUS_FILES=(
  "/corpus/lean_corpus.txt"
  "/corpus/python_corpus.txt"
)

echo "================================================================"
echo "🦾 ЗАПУСК ОПТИМИЗИРОВАННОГО ТЕСТИРОВАНИЯ (3090 Ti Edition)"
echo "⚙️ Контекст: $CTX | Потоков: $THREADS"
echo "================================================================"
echo ""

# echo "=== DEBUG START ================================================"
# $BENCH_BIN --help
# $PPL_BIN --help
# echo "=== DEBUG END =================================================="
# echo ""

# Вывод диагностической информации
echo "=== ДИАГНОСТИКА ПАМЯТИ ==="
nvidia-smi --query-gpu=name,memory.total,memory.free,memory.used --format=csv
echo "========================"
echo ""

echo "=== ПРОВЕРКА МОДЕЛЕЙ ==="
for model in "${MODELS[@]}"; do
  model_path="${MODEL_DIR}/${model}"
  if [[ -f "$model_path" ]]; then
    file_size=$(du -h "$model_path" | cut -f1)
    echo "✅ $model - $file_size"
  else
    echo "❌ $model - НЕ НАЙДЕН"
  fi
done
echo "======================="
echo ""


for model in "${MODELS[@]}"; do

  model_path="${MODEL_DIR}/${model}"
  # Проверяем, существует ли файл модели
  if [[ ! -f "$model_path" ]]; then
    echo "⚠️  Файл модели не найден: $model. Пропускаем."
    continue
  fi

  echo ""
  echo "🟡 МОДЕЛЬ: $model"

  # Безопасные настройки для 24GB VRAM
  model_lower=$(echo "$model" | tr '[:upper:]' '[:lower:]')
  
  if [[ $model_lower == *"32b"* ]]; then
    # 32B модели
    echo "⚡ 32B детектирована. Ставим NGL=$CURRENT_NGL (баланс памяти под контекст)."

    if [[ $CTX -gt 8192 ]]; then
      CURRENT_NGL=40
      GEN_TOKENS=64
    else
      CURRENT_NGL=55
      GEN_TOKENS=128
    fi

  elif [[ $model_lower == *"70b"* ]]; then
    # 70B модели
    if [[ $model_lower == *"q3_k_l"* ]]; then
      CURRENT_NGL=30
    else
      CURRENT_NGL=35
    fi
    echo "📦 70B детектирована. Ставим NGL=$CURRENT_NGL (CPU+GPU гибрид)."
    GEN_TOKENS=128  # Для 70B меньше токенов для быстрого теста
  else
    CURRENT_NGL=20
    GEN_TOKENS=64
    echo "❓ Неизвестный размер. Ставим безопасный NGL=$CURRENT_NGL."
  fi

  echo "[1/2] Замер производительности..."
  
  # Используем timeout для защиты от зависаний
  timeout 300 $BENCH_BIN \
    -m "$model_path" \
    -p $CTX \
    -n $GEN_TOKENS \
    -ngl $CURRENT_NGL \
    -t $THREADS \
    -fa \
    --verbose 2>&1 || {
      echo "⚠️ Бенчмарк завершился с ошибкой или таймаутом"
      # Продолжаем тесты, несмотря на ошибку бенчмарка
    }
  
  # Пауза между тестами
  echo "⏸️  Пауза 10 сек..."
  sleep 10
  
  echo ""
  echo "[2/2] Замер Perplexity (PPL)..."
  
  for corpus_file in "${CORPUS_FILES[@]}"; do
    if [[ -f "$corpus_file" ]]; then
      echo "--> Файл: $(basename "$corpus_file")"
      start_time=$(date +%s)
      
      # Запуск замера качества с логированием
      log_file="${RESULTS_DIR}/ppl_${model}_$(basename "$corpus_file")_$(date +%Y%m%d_%H%M%S).log"
      
      timeout 600 $PPL_BIN \
        -m "$model_path" \
        -f "$corpus_file" \
        -c $CTX \
        -ngl $DEFAULT_NGL \
        -t $THREADS \
        -fa 2>&1 | tee "$log_file" || {
          echo "⚠️ Perplexity тест завершился с ошибкой или таймаутом"
        }
      
      end_time=$(date +%s)
      elapsed=$((end_time - start_time))
      echo "⏱ Время теста: $((elapsed/60)) мин. $((elapsed%60)) сек."
      
      # Извлекаем результат из лога
      if [[ -f "$log_file" ]] && grep -q "Final estimate:" "$log_file"; then
        ppl_result=$(grep "Final estimate:" "$log_file" | tail -1 | grep -o "PPL = [0-9.]*" | cut -d' ' -f3)
        echo "🎯 Результат PPL: ${ppl_result}"
      fi
    else
      echo "⚠️ Файл $corpus_file не найден!"
    fi
    
    # Пауза между корпусами
    echo "⏸️  Пауза 5 сек..."
    sleep 5
  done

  echo "----------------------------------------------------------------"
  echo "✅ Завершено: $model"
  
  # Пауза между моделями для охлаждения GPU
  echo "❄️ Охлаждение GPU (30 сек)..."
  sleep 30
done

echo ""
echo "🎉 ВСЕ ТЕСТЫ ВЫПОЛНЕНЫ!"
echo "📁 Логи сохранены в: $RESULTS_DIR"
