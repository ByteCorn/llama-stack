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

# Идеальная функция расчета параметров для RTX 3090 Ti (24GB VRAM)
# calculate_model_params() {
#     local model="$1"
#     local ctx="$2"
#     local model_lower=$(echo "$model" | tr '[:upper:]' '[:lower:]')
    
#     # Базовая диагностика модели
#     local model_size=$(get_model_size "$model_lower")
#     local quant_type=$(get_quantization_type "$model_lower")
    
#     # Расчет параметров
#     if [[ "$model_size" == "32B" ]]; then
#         # 32B модели: максимальная загрузка GPU при балансе с контекстом
#         case $quant_type in
#             "q2"|"q3")
#                 # Низкобитные квантования - можно больше слоев
#                 if [[ $ctx -le 4096 ]]; then
#                     CURRENT_NGL=80
#                     GEN_TOKENS=256
#                 elif [[ $ctx -le 8192 ]]; then
#                     CURRENT_NGL=65
#                     GEN_TOKENS=192
#                 elif [[ $ctx -le 16384 ]]; then
#                     CURRENT_NGL=50
#                     GEN_TOKENS=128
#                 else
#                     CURRENT_NGL=35
#                     GEN_TOKENS=64
#                 fi
#                 ;;
#             "q4"|"q5")
#                 # Средние квантования
#                 if [[ $ctx -le 4096 ]]; then
#                     CURRENT_NGL=70
#                     GEN_TOKENS=256
#                 elif [[ $ctx -le 8192 ]]; then
#                     CURRENT_NGL=55
#                     GEN_TOKENS=192
#                 elif [[ $ctx -le 16384 ]]; then
#                     CURRENT_NGL=40
#                     GEN_TOKENS=128
#                 else
#                     CURRENT_NGL=25
#                     GEN_TOKENS=64
#                 fi
#                 ;;
#             "q6"|"q8"|"fp16")
#                 # Высокие квантования
#                 if [[ $ctx -le 4096 ]]; then
#                     CURRENT_NGL=60
#                     GEN_TOKENS=192
#                 elif [[ $ctx -le 8192 ]]; then
#                     CURRENT_NGL=45
#                     GEN_TOKENS=128
#                 elif [[ $ctx -le 16384 ]]; then
#                     CURRENT_NGL=30
#                     GEN_TOKENS=96
#                 else
#                     CURRENT_NGL=20
#                     GEN_TOKENS=64
#                 fi
#                 ;;
#             *)
#                 # По умолчанию для 32B
#                 if [[ $ctx -le 8192 ]]; then
#                     CURRENT_NGL=55
#                     GEN_TOKENS=128
#                 else
#                     CURRENT_NGL=40
#                     GEN_TOKENS=64
#                 fi
#                 ;;
#         esac
#         echo "⚡ 32B модель (${quant_type}) | Контекст: ${ctx} → NGL: ${CURRENT_NGL}, Токенов: ${GEN_TOKENS}"
        
#     elif [[ "$model_size" == "70B" ]]; then
#         # 70B модели: гибридный режим CPU+GPU с приоритетом на скорость
#         case $quant_type in
#             "q2"|"q3")
#                 if [[ $ctx -le 4096 ]]; then
#                     CURRENT_NGL=45
#                     GEN_TOKENS=192
#                 elif [[ $ctx -le 8192 ]]; then
#                     CURRENT_NGL=35
#                     GEN_TOKENS=128
#                 elif [[ $ctx -le 16384 ]]; then
#                     CURRENT_NGL=25
#                     GEN_TOKENS=96
#                 else
#                     CURRENT_NGL=18
#                     GEN_TOKENS=64
#                 fi
#                 ;;
#             "q4"|"q5")
#                 if [[ $ctx -le 4096 ]]; then
#                     CURRENT_NGL=40
#                     GEN_TOKENS=160
#                 elif [[ $ctx -le 8192 ]]; then
#                     CURRENT_NGL=30
#                     GEN_TOKENS=128
#                 elif [[ $ctx -le 16384 ]]; then
#                     CURRENT_NGL=22
#                     GEN_TOKENS=96
#                 else
#                     CURRENT_NGL=15
#                     GEN_TOKENS=64
#                 fi
#                 ;;
#             "q6"|"q8"|"fp16")
#                 if [[ $ctx -le 4096 ]]; then
#                     CURRENT_NGL=35
#                     GEN_TOKENS=128
#                 elif [[ $ctx -le 8192 ]]; then
#                     CURRENT_NGL=25
#                     GEN_TOKENS=96
#                 elif [[ $ctx -le 16384 ]]; then
#                     CURRENT_NGL=18
#                     GEN_TOKENS=64
#                 else
#                     CURRENT_NGL=12
#                     GEN_TOKENS=48
#                 fi
#                 ;;
#             *)
#                 # По умолчанию для 70B
#                 if [[ $model_lower == *"q3_k_l"* ]]; then
#                     CURRENT_NGL=35
#                 else
#                     CURRENT_NGL=30
#                 fi
#                 GEN_TOKENS=128
#                 ;;
#         esac
#         echo "📦 70B модель (${quant_type}) | Контекст: ${ctx} → NGL: ${CURRENT_NGL}, Токенов: ${GEN_TOKENS}"
        
#     elif [[ "$model_size" == "13B" ]] || [[ "$model_size" == "14B" ]]; then
#         # 13B-14B модели: почти полная загрузка на GPU
#         if [[ $ctx -le 4096 ]]; then
#             CURRENT_NGL=95
#             GEN_TOKENS=512
#         elif [[ $ctx -le 8192 ]]; then
#             CURRENT_NGL=90
#             GEN_TOKENS=384
#         elif [[ $ctx -le 16384 ]]; then
#             CURRENT_NGL=85
#             GEN_TOKENS=256
#         else
#             CURRENT_NGL=80
#             GEN_TOKENS=192
#         fi
#         echo "🚀 ${model_size} модель | Контекст: ${ctx} → NGL: ${CURRENT_NGL}, Токенов: ${GEN_TOKENS}"
        
#     elif [[ "$model_size" == "7B" ]] || [[ "$model_size" == "8B" ]]; then
#         # 7B-8B модели: полная загрузка на GPU
#         CURRENT_NGL=999  # Все слои на GPU (автоопределение)
#         GEN_TOKENS=512
#         echo "⚡ ${model_size} модель | Контекст: ${ctx} → NGL: auto (все слои), Токенов: ${GEN_TOKENS}"
        
#     else
#         # Неизвестный размер: безопасные консервативные значения
#         if [[ $ctx -le 4096 ]]; then
#             CURRENT_NGL=40
#             GEN_TOKENS=128
#         elif [[ $ctx -le 8192 ]]; then
#             CURRENT_NGL=30
#             GEN_TOKENS=96
#         else
#             CURRENT_NGL=20
#             GEN_TOKENS=64
#         fi
#         echo "❓ Неизвестный размер модели | Контекст: ${ctx} → NGL: ${CURRENT_NGL}, Токенов: ${GEN_TOKENS}"
#     fi
    
#     # Дополнительные проверки безопасности
#     validate_parameters "$model" "$ctx" "$CURRENT_NGL" "$GEN_TOKENS"
# }

# Вспомогательные функции
# get_model_size() {
#     local model_lower="$1"
    
#     # Определение размера модели по названию
#     if [[ $model_lower =~ 1[.]?[0-9]?b ]]; then
#         echo "1B"
#     elif [[ $model_lower =~ 2[.]?[0-9]?b ]]; then
#         echo "2B"
#     elif [[ $model_lower =~ 3[.]?[0-9]?b ]]; then
#         echo "3B"
#     elif [[ $model_lower =~ 4[.]?[0-9]?b ]]; then
#         echo "4B"
#     elif [[ $model_lower =~ 6[.]?[0-9]?b ]]; then
#         echo "6B"
#     elif [[ $model_lower =~ 7[.]?[0-9]?b ]]; then
#         echo "7B"
#     elif [[ $model_lower =~ 8[.]?[0-9]?b ]]; then
#         echo "8B"
#     elif [[ $model_lower =~ 10[.]?[0-9]?b ]] || [[ $model_lower =~ 11[.]?[0-9]?b ]] || [[ $model_lower =~ 12[.]?[0-9]?b ]]; then
#         echo "12B"
#     elif [[ $model_lower =~ 13[.]?[0-9]?b ]] || [[ $model_lower =~ 14[.]?[0-9]?b ]]; then
#         echo "13B"
#     elif [[ $model_lower =~ 20[.]?[0-9]?b ]]; then
#         echo "20B"
#     elif [[ $model_lower =~ 30[.]?[0-9]?b ]] || [[ $model_lower =~ 32[.]?[0-9]?b ]] || [[ $model_lower =~ 34[.]?[0-9]?b ]]; then
#         echo "32B"
#     elif [[ $model_lower =~ 40[.]?[0-9]?b ]]; then
#         echo "40B"
#     elif [[ $model_lower =~ 60[.]?[0-9]?b ]] || [[ $model_lower =~ 65[.]?[0-9]?b ]]; then
#         echo "65B"
#     elif [[ $model_lower =~ 70[.]?[0-9]?b ]]; then
#         echo "70B"
#     elif [[ $model_lower =~ 120[.]?[0-9]?b ]] || [[ $model_lower =~ 130[.]?[0-9]?b ]]; then
#         echo "120B"
#     else
#         echo "UNKNOWN"
#     fi
# }

# get_quantization_type() {
#     local model_lower="$1"
    
#     # Определение типа квантования
#     if [[ $model_lower =~ q2_ ]]; then
#         echo "q2"
#     elif [[ $model_lower =~ q3_ ]]; then
#         echo "q3"
#     elif [[ $model_lower =~ q4_ ]]; then
#         echo "q4"
#     elif [[ $model_lower =~ q5_ ]]; then
#         echo "q5"
#     elif [[ $model_lower =~ q6_ ]]; then
#         echo "q6"
#     elif [[ $model_lower =~ q8_ ]]; then
#         echo "q8"
#     elif [[ $model_lower =~ f16 ]] || [[ $model_lower =~ fp16 ]]; then
#         echo "fp16"
#     elif [[ $model_lower =~ f32 ]] || [[ $model_lower =~ fp32 ]]; then
#         echo "fp32"
#     else
#         echo "unknown"
#     fi
# }

# validate_parameters() {
#     local model="$1"
#     local ctx="$2"
#     local ngl="$3"
#     local gen_tokens="$4"
    
#     # Корректировка для очень больших контекстов
#     if [[ $ctx -gt 32768 ]]; then
#         echo "⚠️  ОЧЕНЬ БОЛЬШОЙ КОНТЕКСТ (${ctx})! Уменьшаем NGL на 30%"
#         CURRENT_NGL=$((ngl * 70 / 100))
#         if [[ $CURRENT_NGL -lt 10 ]]; then
#             CURRENT_NGL=10
#         fi
#         GEN_TOKENS=$((gen_tokens * 60 / 100))
#         if [[ $GEN_TOKENS -lt 32 ]]; then
#             GEN_TOKENS=32
#         fi
#     fi
    
#     # Минимальные гарантированные значения
#     if [[ $CURRENT_NGL -lt 1 ]]; then
#         CURRENT_NGL=1
#     fi
    
#     if [[ $GEN_TOKENS -lt 16 ]]; then
#         GEN_TOKENS=16
#     fi
    
#     # Максимальные значения для безопасности
#     if [[ $CURRENT_NGL -gt 999 ]]; then
#         CURRENT_NGL=999  # Специальное значение для "все слои"
#     fi
    
#     if [[ $GEN_TOKENS -gt 1024 ]]; then
#         GEN_TOKENS=1024
#     fi
# }


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


  # # Вызов функции расчета параметров
  # calculate_model_params "$model" "$CTX"
    
  echo "[1/2] Замер производительности с параметрами:"
  echo "      NGL=$CURRENT_NGL, GEN_TOKENS=$GEN_TOKENS, CTX=$CTX, THREADS=$THREADS"

  # # Безопасные настройки для 24GB VRAM
  # model_lower=$(echo "$model" | tr '[:upper:]' '[:lower:]')
  
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

  # echo "[1/2] Замер производительности..."
  
  # Используем timeout для защиты от зависаний
  timeout 3600 $BENCH_BIN \
    -m "$model_path" \
    -p $CTX \
    -n $GEN_TOKENS \
    -ngl $CURRENT_NGL \
    -t $THREADS \
    -fa auto \
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
      
      $PPL_BIN \
        -m "$model_path" \
        -f "$corpus_file" \
        -c $CTX \
        -ngl $DEFAULT_NGL \
        -t $THREADS \
        -fa 2>&1 | tee "$log_file" || {
          echo "⚠️ Perplexity тест завершился с ошибкой"
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
