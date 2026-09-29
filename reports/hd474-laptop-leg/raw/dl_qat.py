import threading, time
from huggingface_hub import snapshot_download
INC = ["gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf", "mmproj-BF16.gguf", "config.json"]
t0 = time.time()
p = snapshot_download("unsloth/gemma-4-26B-A4B-it-qat-GGUF",
                      local_dir=r"D:/llm/models/unsloth/gemma-4-26B-A4B-it-qat-GGUF",
                      allow_patterns=INC, max_workers=3)
print("DONE", p, "%.0fs" % (time.time() - t0), flush=True)
