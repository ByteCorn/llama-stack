#!/bin/bash

mkdir -p llama_cpp_models

hf download Qwen/Qwen2.5-Coder-32B-Instruct-GGUF \
  qwen2.5-coder-32b-instruct-q5_k_m.gguf \
  --local-dir ./llama_cpp_models

hf download bartowski/Qwen2.5-Coder-32B-Instruct-abliterated-GGUF \
  Qwen2.5-Coder-32B-Instruct-abliterated-Q5_K_M.gguf \
  --local-dir ./llama_cpp_models


hf download mradermacher/Llama_3.x_70b_L3.3-Dolphin-Eva_fusion_v2-GGUF \
  Llama_3.x_70b_L3.3-Dolphin-Eva_fusion_v2.Q3_K_L.gguf \
  --local-dir ./llama_cpp_models

hf download tensorblock/Llama-3.3-70B-Instruct-abliterated-GGUF \
  Llama-3.3-70B-Instruct-abliterated-Q3_K_M.gguf \
  --local-dir ./llama_cpp_models
