# Spike: конвертация GigaAM v3_e2e_ctc в CoreML

**Дата:** 2026-07-16 · **Вердикт: ✅ работает** · Железо: MacBook Air (Apple Silicon, 8 ГБ)

## Результат

| Метрика | PyTorch (CPU) | CoreML (ANE/GPU) |
|---|---|---|
| Инференс 25с аудио | ~1200 мс | **102 мс** (×245 реального времени) |
| Размер модели | 433 МБ ckpt | **422 МБ .mlpackage** |
| Пик ОЗУ (torch-прогон) | ~1.1 ГБ | — (CoreML ниже) |
| Совпадение argmax-токенов | — | 98.4% (fp16-округление) |
| Декодированный текст | эталон | **идентичен**, с пунктуацией |

Модель: `v3_e2e_ctc` (Сбер GigaAM, MIT) — русский ASR **с пунктуацией/капитализацией из
коробки** («ёлочки», ё, пометки «э-э»). Форма входа **статическая** (25с окно) — динамические
длины CoreML-конвертация не осилила (для Voica ок: паддим диктовку до окна, реальная длина
передаётся в `feature_lengths`).

## Грабли по дороге (9 итераций)

1. `GigaAM.forward()` ожидает **сырой wav** — препроцессор (мел 64 бина) вызывается внутри.
   Для экспорта использовать **`forward_for_export(features, lengths)`** (encoder+head).
2. Не вызывать `transcribe()` до трейса — `@inference_mode` кэширует rotary cos/sin как
   inference-тензоры, трейс падает. Сначала прогреть через `forward_for_export` под `no_grad`.
3. Трейсить в контексте **`model.encoder.onnx_export_mode()`**.
4. `torch 2.13` несовместим с coremltools 9 (`aten::Int` баг) → **`torch 2.7.x`**.
5. Путь `torch.jit.trace` мёртв даже на 2.7 (тот же `int`-баг в pos_enc) →
   использовать **`torch.export.export` + `ep.run_decompositions({})`** (подсказка из
   ошибки «Provided Dialect: TRAINING»).
6. Пример входа должен быть **`.contiguous()`** (EXIR: «non-contiguous dim order»), но
   НЕ вставлять `.contiguous()` в сам forward — родит `alias`-ноду.
7. Финальный блокер: **32 `aten.alias`-ноды** в декомпозированном графе, coremltools их
   не умеет → хирургия FX-графа: `replace_all_uses_with(args[0])` + `erase_node`.

## Рабочий скрипт конвертации

Окружение: python3.13 venv; `torch==2.7.*`, `torchaudio==2.7.*`, `coremltools>=9`,
gigaam из git-репо (`--no-deps` + hydra-core, omegaconf, pydub, sentencepiece, numpy,
tqdm, soundfile).

```python
import gigaam, torch, numpy as np
import coremltools as ct

model = gigaam.load_model("v3_e2e_ctc", device="cpu"); model.eval()
wav, length = model.prepare_wav("sample_25s.wav")
with torch.no_grad():
    features, feat_len = model.preprocessor(wav, length)
    features = features.contiguous()

class W(torch.nn.Module):
    def __init__(s, m): super().__init__(); s.m = m
    def forward(s, features, feature_lengths):
        return s.m.forward_for_export(features, feature_lengths.to(torch.long))
w = W(model).eval()

with model.encoder.onnx_export_mode(), torch.no_grad():
    ep = torch.export.export(w, (features, feat_len.to(torch.int32)))
    ep = ep.run_decompositions({})
    gm = ep.graph_module
    for node in list(gm.graph.nodes):                      # alias — no-op, выкидываем
        if node.op == "call_function" and "alias" in str(node.target):
            node.replace_all_uses_with(node.args[0])
            gm.graph.erase_node(node)
    gm.graph.lint(); gm.recompile()
    mlm = ct.convert(ep, minimum_deployment_target=ct.target.macOS14)
mlm.save("gigaam_v3_e2e.mlpackage")
```

Выход: `(log_probs [1, 625, 257], enc_len)`. Декод: CTC-collapse (blank = 256, дедуп) →
sentencepiece-токенизатор (`v3_e2e_ctc_tokenizer.model`, 236 КБ).

## Что остаётся для интеграции в Voica

- Мел-спектрограмма (64 бина, как их FeatureExtractor) на Swift/Accelerate.
- CTC greedy decode + sentencepiece-декод на Swift (или свой BPE-ридер — формат простой).
- Загрузчик модели (docs → Application Support, 422 МБ, прогресс).
- Паддинг диктовки до 25с окна (или экспорт 2–3 фиксированных окон).
- Готовый .mlpackage лежит в `~/.cache/gigaam/gigaam_v3_e2e.mlpackage` (локально у Ивана).
