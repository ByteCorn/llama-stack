#!/bin/bash

# Прямые пути к бинарникам
BENCH_BIN="/app/llama-bench"
PPL_BIN="/app/llama-perplexity"
MODEL_DIR="/models"

# Используем контекст из Docker Compose. Если не задан, ставим безопасные 8192.
# ВАЖНО: При значении 32768+ тест PPL будет идти долго, но уже не "бесконечно".
CTX="${LLAMA_ARG_CTX_SIZE:-8192}"

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
echo "⚙️ Контекст: $CTX | Потоков: $LLAMA_ARG_THREADS"
echo "================================================================"

for model in "${MODELS[@]}"; do
  echo ""
  echo "🟡 МОДЕЛЬ: $model"
  
  # --- Динамический расчет NGL под 24GB VRAM ---
  # 32B модели весят ~22GB. Чтобы оставить место под KV-кеш $CTX, ставим NGL 70-80.
  if [[ $model == *"32b"* || $model == *"32B"* ]]; then
     CURRENT_NGL=75
     echo "⚡ 32B детектирована. Ставим NGL=$CURRENT_NGL (баланс памяти под контекст)."
  
  # 70B модели весят 32-35GB. Все не влезут. Максимум для 3090 Ti — около 45 слоев.
  elif [[ $model == *"70b"* || $model == *"70B"* ]]; then
     # Для более тяжелой версии (Q3_K_L) чуть меньше слоев
     if [[ $model == *"Q3_K_L"* ]]; then
        CURRENT_NGL=40
     else
        CURRENT_NGL=45
     fi
     echo "📦 70B детектирована. Ставим NGL=$CURRENT_NGL (CPU+GPU гибрид)."
  else
     CURRENT_NGL=33
     echo "❓ Неизвестный размер. Ставим безопасный NGL=$CURRENT_NGL."
  fi

  # 1. Замер скорости (llama-bench)
  echo "[1/2] Замер производительности..."
  # -p $CTX замеряет скорость обработки именно твоего рабочего окна
  $BENCH_BIN -m "$MODEL_DIR/$model" -p $CTX -n 128 -ngl $CURRENT_NGL
  
  echo ""
  echo "[2/2] Замер Perplexity (PPL)..."
  
  for corpus_file in "${CORPUS_FILES[@]}"; do
    if [ -f "$corpus_file" ]; then
      echo "--> Файл: $corpus_file"
      start_time=$(date +%s)
      
      # Запуск замера качества
      $PPL_BIN -m "$MODEL_DIR/$model" -f "$corpus_file" -c $CTX -ngl $CURRENT_NGL -fa auto
      
      end_time=$(date +%s)
      elapsed=$((end_time - start_time))
      echo "⏱ Время теста файла: $((elapsed/60)) мин. $((elapsed%60)) сек."
    else
      echo "⚠️ Файл $corpus_file не найден!"
    fi
  done

  echo "----------------------------------------------------------------"
  echo "✅ Завершено: $model"
done

echo "🎉 ВСЕ ТЕСТЫ ВЫПОЛНЕНЫ!"
