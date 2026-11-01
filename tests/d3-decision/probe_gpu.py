"""Small gfx1151 BF16 probe, using the inference package's Python closure."""

import json
import torch


def main():
    assert torch.cuda.is_available(), "ROCm device is unavailable"
    properties = torch.cuda.get_device_properties(0)
    arch = properties.gcnArchName.split(":", 1)[0]
    assert arch == "gfx1151", arch
    assert torch.cuda.is_bf16_supported(), "BF16 is unavailable"
    with torch.inference_mode():
        tensor = torch.ones((32, 32), dtype=torch.bfloat16, device="cuda:0")
        result = tensor @ tensor
        torch.cuda.synchronize()
        error = (result.float() - 32).abs().max().item()
    assert error == 0, error
    print(json.dumps({"torch": torch.__version__, "rocm": torch.version.hip,
                      "device": properties.name, "arch": arch, "bf16_supported": True,
                      "bf16_matmul_max_error": error,
                      "allocated_bytes": torch.cuda.memory_allocated()}, indent=2))


if __name__ == "__main__":
    main()
