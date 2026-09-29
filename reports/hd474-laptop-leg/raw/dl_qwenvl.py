from huggingface_hub import snapshot_download
import time
t0 = time.time()
p = snapshot_download("unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF",
                      local_dir=r"D:/llm/models/unsloth/Qwen3-VL-30B-A3B-Instruct-GGUF",
                      allow_patterns=["Qwen3-VL-30B-A3B-Instruct-UD-Q4_K_XL.gguf",
                                      "mmproj-BF16.gguf", "config.json"],
                      max_workers=3)
print("DONE", p, "%.0fs" % (time.time() - t0), flush=True)
