"""CPU contract checks against the released Ultra prompt formatter.

Only the named D3 class is compiled from the patched vLLM module. GPU, vLLM
imports and model weights are unnecessary for testing this request boundary.
The full modules are also syntax checked; the appliance import/HTTP/GPU gates
remain separate, because these checks cannot establish kernel correctness.
"""

from __future__ import annotations

import ast
import asyncio
import importlib.util
import json
import math
from pathlib import Path
import string
import sys
from types import SimpleNamespace as NS
import unittest


SOURCE, FORMAT = map(Path, sys.argv[1:3])
sys.argv[1:] = []


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    sys.modules[name] = loaded
    spec.loader.exec_module(loaded)
    return loaded


reference = module("d3_checkpoint_format", FORMAT)
types = module(
    "d3_question_types",
    SOURCE / "vllm/entrypoints/openai/decisions/question_types.py",
)


class Tokenizer:
    """Text-preserving tokenizer; compares formatting independently of weights."""

    def apply_chat_template(self, messages, **kwargs):
        assert kwargs == {
            "tokenize": False,
            "add_generation_prompt": True,
            "enable_thinking": False,
        }
        def content(value):
            if isinstance(value, str):
                return value
            return "".join(
                item["text"] if item["type"] == "text" else "<|vision_end|>"
                for item in value
            )
        return "".join(
            f"<|im_start|>{m['role']}\n{content(m['content'])}<|im_end|>\n"
            for m in messages
        ) + "<|im_start|>assistant\n"

    def encode(self, text, **kwargs):
        return list(map(ord, text))

    def __call__(self, text, **kwargs):
        return {
            "input_ids": self.encode(text),
            "offset_mapping": [(i, i + 1) for i in range(len(text))],
        }


class ReadStrategy:
    def __init__(self, context):
        self.context = context


def named_class(path, name, namespace):
    tree = ast.parse(path.read_text())
    selected = [n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == name]
    assert len(selected) == 1
    unit = ast.Module(body=[ast.ImportFrom(module="__future__", names=[ast.alias(name="annotations")], level=0), *selected], type_ignores=[])
    exec(compile(ast.fix_missing_locations(unit), str(path), "exec"), namespace)
    return namespace[name]


Strategy = named_class(
    SOURCE / "vllm/entrypoints/openai/decisions/strategies.py",
    "D3Strategy",
    {
        "ReadStrategy": ReadStrategy,
        "asyncio": asyncio,
        "math": math,
        "json": json,
        "StructuredDecisionError": types.StructuredDecisionError,
        "state_text": lambda state: state if isinstance(state, str) else json.dumps(state, ensure_ascii=False),
        "DecisionLimits": NS,
        "PoolingParams": NS,
        "QuestionRead": NS,
        "label_softmax": types.label_softmax,
        "tokens_input": lambda ids, **kwargs: {"prompt_token_ids": ids},
    },
)


class Spec(NS):
    def model_copy(self, update):
        return Spec(**(vars(self) | update))


def question(kind="choice", criteria=None, instructions="Which?", qid="q"):
    if criteria is None and kind == "choice":
        criteria = {"a": None, "b": "é"}
    spec = Strategy.normalize_spec(Spec(type=kind, criteria=criteria, instructions=instructions))
    return types.build_question(qid, kind, spec.instructions, spec.criteria, 255, labeled=False)


def strategy():
    tokenizer = Tokenizer()
    decision = {
        "codes": reference.candidate_codes()[:255],
        "temperature": 1.0,
        "temperature_by_questions": {"max_questions": [1, 4, 16], "temperature": [1.046, 1.0, 1.0, 1.0]},
        "attention_mode": "prefix_bidir",
        "prompt_layout": "header-v1",
    }
    calls = []

    async def encode(prompt, params, request_id, **kwargs):
        await asyncio.sleep(0)
        calls.append((prompt, params))
        logits = [0.0, 1.0] + [-100.0] * 253
        yield NS(error=None, outputs=NS(data=NS(tolist=lambda: logits)))

    context = NS(
        engine_client=NS(model_config=NS(hf_config=NS(decision_config=decision), max_model_len=131072), encode=encode),
        online_renderer=NS(renderer=NS(get_tokenizer=lambda: tokenizer)),
    )
    return Strategy(context), calls


def rendered(q):
    texts, _ = Strategy._options(object.__new__(Strategy), q)
    # The native runtime normalizes Score to a Choice with level texts.
    if q.type.name == "noul":
        criteria = {"false": texts[0], "true": texts[1]}
        kind = "noul"
    else:
        criteria = dict.fromkeys(texts)
        kind = "choice"
    return {"type": kind, "instructions": q.instructions, "criteria": criteria}


class Contract(unittest.TestCase):
    def test_syntax(self):
        for relative in (
            "vllm/entrypoints/openai/decisions/strategies.py",
            "vllm/entrypoints/generate/structured_decisions/serving.py",
            "vllm/model_executor/models/config.py",
            "vllm/model_executor/models/d3.py",
            "vllm/transformers_utils/model_arch_config_convertor.py",
            "vllm/v1/worker/gpu/model_states/default.py",
        ):
            compile((SOURCE / relative).read_text(), relative, "exec")

    def test_prompt_matches_release(self):
        runtime, _ = strategy()
        questions = [
            question(),
            question("noul", {"true": {"ok": True}, "false": 0}, "Urgent?"),
            question("score", ["low", {"high": 2}], {"score": "tone"}),
        ]
        header = [rendered(q) for q in questions]
        for state in ("a state", "", {"clé": "été", "n": 0}):
            for q in questions:
                expected = reference.render(runtime.tokenizer, state, rendered(q), runtime.codes, header)
                actual = runtime._prompt(runtime.render_state(state), q, [], questions)
                self.assertEqual(actual, expected)

    def test_json_descriptions_are_json(self):
        q = question(criteria={"false": False, "obj": {"clé": 1}}, instructions={"ask": True})
        self.assertEqual(q.instructions, '{"ask": true}')
        self.assertEqual(q.options[0].description, "false")
        self.assertEqual(q.options[1].description, '{"clé": 1}')

    def test_header_lives_inside_state_range(self):
        runtime, _ = strategy()
        questions = [question(), question("score", ["low", "high"])]
        prompt = runtime._prompt("state é", questions[0], [], questions)
        ids, count = runtime._encode(prompt, "state é")
        prefix = "".join(map(chr, ids[:count]))
        self.assertIn("Questions in this request:", prefix)
        self.assertIn("   - low\n   - high", prefix)
        self.assertTrue(prefix.endswith("State:\nstate é"))
        self.assertTrue("".join(map(chr, ids[count:])).startswith("\n\nQuestion:"))

    def test_media_omits_header(self):
        runtime, _ = strategy()
        prompt = runtime._prompt("photo", question(), ["image"])
        self.assertNotIn("Questions in this request:", prompt)

    def test_temperature_boundaries(self):
        runtime, _ = strategy()
        self.assertEqual([runtime._temperature_for(n) for n in (1, 2, 4, 5, 16, 17, 64)], [1.046, 1, 1, 1, 1, 1, 1])

    def test_answers_follow_d3_contract(self):
        runtime, _ = strategy()
        choice = question(criteria={"a": None, "b": None})
        answer = runtime.systemone_answer(choice, [0.25, 0.75], None)
        expected = reference.to_answer(rendered(choice), [0.25, 0.75])
        expected["confidence"] = 1 + (0.25 * math.log(0.25) + 0.75 * math.log(0.75)) / math.log(2)
        self.assertEqual(answer, expected)
        noul = question("noul")
        self.assertEqual(runtime.systemone_answer(noul, [0.75, 0.25], None), {"type": "noul", "noul": 0.75})
        score = question("score", [{"z": 2, "a": 1}, "high"])
        answer = runtime.systemone_answer(score, [0.25, 0.75], [{"z": 2, "a": 1}, "high"])
        self.assertEqual(answer["legend"], {"0": '{"a":1,"z":2}', "1": "high"})
        self.assertEqual(answer["score"], 0.75)
        self.assertAlmostEqual(answer["confidence"], expected["confidence"])

    def test_concurrent_request_temperatures(self):
        runtime, calls = strategy()
        async def run():
            async def read(count):
                return await runtime.read([question(qid=str(i)) for i in range(count)], None, "state", request_id=str(count), chat_template_kwargs=None, lora_request=None, priority=0)
            return await asyncio.gather(read(1), read(4))
        one, four = asyncio.run(run())
        self.assertAlmostEqual(one[0].probs[1], 1 / (1 + math.exp(-1 / 1.046)))
        self.assertAlmostEqual(four[0].probs[1], 1 / (1 + math.exp(-1)))
        self.assertEqual(runtime.temperature, 1.0)
        self.assertTrue(all(call[1].extra_kwargs["d3_state_tokens"] > 0 for call in calls))

    def test_state_ranges_and_bool(self):
        class Default:
            def __init__(self): pass
            def add_request(self, *args): pass
        cls = named_class(
            SOURCE / "vllm/model_executor/models/d3.py",
            "D3PrefixBidirModelState",
            {"DefaultModelState": Default, "STATE_TOKENS": "d3_state_tokens", "logger": NS(debug_once=lambda *args: None)},
        )
        model = cls()
        def add(req, count):
            model.add_request(0, NS(req_id=req, prompt_token_ids=list(range(10)), pooling_params=NS(extra_kwargs={"d3_state_tokens": count})))
        add("valid", 6)
        add("bool", True)
        self.assertEqual(model.blocks["valid"], [(0, 5), (6, 9)])
        self.assertEqual(model.blocks["bool"], [(0, 9)])


if __name__ == "__main__":
    unittest.main()
