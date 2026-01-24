#!/bin/bash

mkdir -p models

hf download Qwen/Qwen2.5-Coder-32B-Instruct-GGUF \
  qwen2.5-coder-32b-instruct-q5_k_m.gguf \
  --local-dir ./models
