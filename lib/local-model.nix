# The fleet's local model endpoints: one place for each address and served
# model id, so the server and every consumer agree (#525, the move to Gufo).
#
# Gufo serves one model per process and answers 404 to a request naming any
# other id, and 400 to a request naming none, so consumers send exactly
# `modelId`. The alternate answers on the same port only while an operator has
# switched it in, never alongside the default.
#
# Local DeepSeek is retired. Remote DeepSeek API routes are independent of
# this local Gufo contract.
{
  endpoint = "http://strix-coordinator:8731";
  modelId = "qwen3.8-flash-next";
  alternates = [
    "qwen3.8-27b"
  ];
}
