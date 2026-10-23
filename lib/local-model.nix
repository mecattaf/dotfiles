# The fleet's local model endpoint: one place for the address and the served
# model id, so the server and every consumer agree (#525, the move to Gufo).
#
# Gufo serves one model per process and answers 404 to a request naming any
# other id, and 400 to a request naming none, so consumers send exactly
# `modelId`. The alternates answer on the same port only while an operator has
# switched them in, never alongside the default.
{
  endpoint = "http://strix:8731";
  modelId = "qwen3.8-flash-next";
  alternates = [
    "qwen3.8-27b"
    "deepseek-v4-flash"
  ];
}
