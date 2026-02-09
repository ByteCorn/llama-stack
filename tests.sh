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
NGL="${LLAMA_ARG_N_GPU_LAYERS:-auto}"
# GEN_TOKENS="${LLAMA_ARG_N_PREDICT:--1}"

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
echo "⚙️ Контекст: $CTX | Загрузка слоёв в видеокарту: $NGL | Потоков: $THREADS"
echo "================================================================"
echo ""

# Вывод диагностической информации
echo "=== ДИАГНОСТИКА ПАМЯТИ ==="
nvidia-smi --query-gpu=name,memory.total,memory.free,memory.used --format=csv
echo "========================"
echo ""

for model in "${MODELS[@]}"; do

  model_path="${MODEL_DIR}/${model}"

  # Проверяем, существует ли файл модели
  if [[ -f "$model_path" ]]; then
    file_size=$(du -h "$model_path" | cut -f1)
    echo "✅ МОДЕЛЬ: $model - $file_size"
  else
    echo "❌ $model - НЕ НАЙДЕН"
  fi

  # --- Расчет NGL под 24GB VRAM ---
  # 32B модели весят ~22GB. Чтобы оставить место под KV-кеш $CTX, ставим NGL 60.
  if [[ $model == *"32b"* || $model == *"32B"* ]]; then 
    N_GPU_LAYERS=60
    echo "⚡ 32B детектирована. Ставим NGL=$N_GPU_LAYERS"
  # 70B модели весят 32-35GB. Все не влезут. Максимум для 3090 Ti — около 45 слоев.
  elif [[ $model == *"70b"* || $model == *"70B"* ]]; then
     # Для более тяжелой версии (Q3_K_L) чуть меньше слоев
    if [[ $model == *"Q3_K_L"* ]]; then
      N_GPU_LAYERS=40
      echo "📦 70B детектирована(Q3_K_L). NGL=$N_GPU_LAYERS"
    else
      N_GPU_LAYERS=45
      echo "📦 70B детектирована. NGL=$N_GPU_LAYERS"
    fi 
  else
     N_GPU_LAYERS=33
     echo "❓ Неизвестный размер. Ставим безопасный NGL=$N_GPU_LAYERS"
  fi

  echo "[1/2] Замер производительности с параметрами:"
  echo "      NGL=$N_GPU_LAYERS, CTX=$CTX, THREADS=$THREADS"
  echo ""

  $BENCH_BIN \
    -m "$model_path" \
    -p $CTX \
    -t $THREADS \
    -ngl $N_GPU_LAYERS \
    -fa auto \
    --verbose 2>&1 || {
      echo "⚠️ Бенчмарк завершился с ошибкой или таймаутом"
      echo ""
      # Продолжаем тесты, несмотря на ошибку бенчмарка
    }

  # Пауза между тестами
  echo "⏸️  Пауза 10 сек..."
  sleep 10

  echo ""
  echo "[2/2] Замер Perplexity (PPL)..."
  echo "      NGL=$NGL, CTX=$CTX, THREADS=$THREADS"
  echo ""

  for corpus_file in "${CORPUS_FILES[@]}"; do
    if [[ -f "$corpus_file" ]]; then
      echo "--> Файл: $(basename "$corpus_file")"
      start_time=$(date +%s)
  
      $PPL_BIN \
        -m "$model_path" \
        -f "$corpus_file" \
        -c $CTX \
        -ngl $NGL \
        -t $THREADS \
        -fa auto 2>&1 || {
          echo "⚠️ Perplexity тест завершился с ошибкой"
        # Продолжаем тесты, несмотря на ошибку бенчмарка
        }

      end_time=$(date +%s)
      elapsed=$((end_time - start_time))
      echo "⏱ Время теста: $((elapsed/60)) мин. $((elapsed%60)) сек."

    else
      echo "⚠️ Файл $corpus_file не найден!"
    fi

    # Пауза между корпусами
    echo "⏸️  Пауза 60 сек..."
    sleep 60
  done

  echo "----------------------------------------------------------------"
  echo "✅ Завершено: $model"

  # Пауза между моделями для охлаждения GPU
  echo "❄️ Охлаждение GPU (10 минут)..."
  sleep 600
done

echo ""
echo "🎉 ВСЕ ТЕСТЫ ВЫПОЛНЕНЫ!"
echo "📁 Логи сохранены в: $RESULTS_DIR"
