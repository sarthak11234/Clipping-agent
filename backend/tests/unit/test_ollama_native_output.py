from types import SimpleNamespace

from src import ai


def _config():
    return SimpleNamespace(
        llm="ollama:qwen3:4b",
        resolve_ollama_base_url=lambda: "http://127.0.0.1:11434/v1",
        ollama_api_key="ollama",
    )


def test_local_ollama_uses_native_json_output():
    # Tool-call retries can leave an assistant message with content=null, which
    # Ollama rejects; grammar-constrained JSON output avoids that history.
    assert ai._uses_native_output("ollama:qwen3:4b")


def test_ollama_cloud_keeps_tool_output():
    # Ollama Cloud accepts response_format but does not enforce the schema.
    assert not ai._uses_native_output("ollama:gpt-oss:20b-cloud")


def test_ollama_model_disables_thinking():
    model = ai._build_transcript_model(_config())
    assert isinstance(model, ai.OllamaModel)
    assert model.settings == {"extra_body": {"reasoning_effort": "none"}}
