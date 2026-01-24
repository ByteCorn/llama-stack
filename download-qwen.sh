#!/bin/bash

mkdir -p models cache
cd models

# Скачать Qwen2.5-32B Q5_K_M (оптимальный баланс скорость/качество)
huggingface-cli download Qwen/Qwen2.5-Coder-32B-Instruct-GGUF \
  qwen2.5-coder-32b-instruct-q5_k_m.gguf \
  --local-dir . --local-dir-use-symlinks False

# Проверка: ~21.5 ГБ файл
ls -lh qwen2.5-coder-32b-instruct-q5_k_m.gguf

