#!/bin/bash

# Прямые пути к бинарникам
BENCH_BIN="/app/llama-bench"
PPL_BIN="/app/llama-perplexity"
MODEL_DIR="/models"

# Используем контекст из Docker Compose. Если не задан, ставим безопасные 8192.
CTX="${LLAMA_ARG_CTX_SIZE:-8192}"
NGL="${LLAMA_ARG_N_GPU_LAYERS:-auto}"
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

  echo "DEBUG_START"
  $BENCH_BIN --help
  echo "DEBUG_END"

  echo ""
  echo "🟡 МОДЕЛЬ: $model"

  echo "[1/2] Замер производительности..."
  $BENCH_BIN -m "$MODEL_DIR/$model" -p $CTX -n 128 -ngl $NGL
  
  echo ""
  echo "[2/2] Замер Perplexity (PPL)..."
  
  for corpus_file in "${CORPUS_FILES[@]}"; do
    if [ -f "$corpus_file" ]; then
      echo "--> Файл: $corpus_file"
      start_time=$(date +%s)
      
      # Запуск замера качества
      $PPL_BIN -m "$MODEL_DIR/$model" -f "$corpus_file" -c $CTX -ngl $NGL -fa auto
      
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
