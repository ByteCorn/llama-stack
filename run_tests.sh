#!/bin/bash

# Список твоих моделей
MODELS=(
  "qwen2.5-coder-32b-instruct-q5_k_m.gguf"
  "Qwen2.5-Coder-32B-Instruct-abliterated-Q5_K_M.gguf"
  "Llama_3.x_70b_L3.3-Dolphin-Eva_fusion_v2.Q3_K_L.gguf"
  "Llama-3.3-70B-Instruct-abliterated-Q3_K_M.gguf"
)

# Файлы для тестирования Perplexity (PPL)
CODE_FILES=(
  "/codes/sat_solver.lean"
  "/codes/role.py"
)

echo "================================================================"
echo "🦾 ЗАПУСК КОМПЛЕКСНОГО ТЕСТИРОВАНИЯ (Speed + PPL Coding)"
echo "================================================================"

for model in "${MODELS[@]}"; do
  echo ""
  echo "🟡 ТЕСТИРУЕМ: $model"
  echo "----------------------------------------------------------------"

  # 1. Замер скорости
  echo "[1/2] Замер производительности (llama-bench)..."
  /llama-bench -m "/models/$model" -p 512 -n 128 -ngl 99
  
  echo ""
  echo "[2/2] Замер качества кода (llama-perplexity)..."
  
  for code_file in "${CODE_FILES[@]}"; do
    if [ -f "$code_file" ]; then
      echo "--> Тестируем на файле: $code_file"
      # -c 4096: оптимальное окно для замера логики
      /llama-perplexity -m "/models/$model" -f "$code_file" -c 4096 -ngl 99
    else
      echo "⚠️ Файл $code_file не найден!"
    fi
    echo ""
  done

  echo "----------------------------------------------------------------"
  echo "✅ Завершено тестирование модели: $model"
  echo "================================================================"
done

echo "🎉 ВСЕ ТЕСТЫ ЗАВЕРШЕНЫ!"
