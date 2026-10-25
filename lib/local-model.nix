# The fleet's local model endpoints: one place for each address and served
# model id, so the server and every consumer agree (#525, the move to Gufo).
#
# Gufo serves one model per process and answers 404 to a request naming any
# other id, and 400 to a request naming none, so consumers send exactly
# `modelId`. The alternate answers on the same port only while an operator has
# switched it in, never alongside the default.
#
# `ds4` is DeepSeek V4.1 Flash 1017 on the ds4 engine (modules/ds4.nix), a
# separate server on its own port: single host on strix-worker with SSD expert
# streaming, started by hand (it stops that host's Gufo units). Nothing
# automated calls it; dsh names it as an explicit route.
{
  endpoint = "http://strix-coordinator:8731";
  modelId = "qwen3.8-flash-next";
  alternates = [
    "qwen3.8-27b"
  ];
  ds4 = {
    endpoint = "http://10.42.0.5:8732";
    modelId = "deepseek-v4.1-flash";
    contextWindow = 32768;
  };
}
