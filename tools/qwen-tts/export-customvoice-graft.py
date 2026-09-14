#!/usr/bin/env python3
"""CPU-only static CustomVoice graft experiment. Never mutates source GGUFs.

Keep Q8 backbone; graft input interfaces are retained at BF16/F32 precision.
The community's additional emotion/activation modifications are not included.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys

# Use the pinned gguf-py checkout through PYTHONPATH; dependencies are numpy and PyYAML.
import numpy as np
import gguf

CODEC = 'talker.codec_embd.weight'
TEXT = 'talker.text_embd.weight'
PROJ = ['talker.text_proj.fc1.weight', 'talker.text_proj.fc1.bias',
        'talker.text_proj.fc2.weight', 'talker.text_proj.fc2.bias']
SPECIAL = [151671, 151672, 151673]
VOICE_ROWS = {'k2so_primary': 3061, 'k2so_dry': 3062,
              'k2so_reassuring': 3063, 'k2so_urgent': 3064}

def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(8 * 1024 * 1024), b''): h.update(b)
    return h.hexdigest()

def datahash(a): return hashlib.sha256(memoryview(np.ascontiguousarray(a))).hexdigest()

def val(reader, key): return reader.get_field(key).contents()

def floats(t, rows=None):
    data = t.data if rows is None else t.data[rows]
    return gguf.dequantize(data, t.tensor_type).astype(np.float32, copy=False)

def project(rows, tensors):
    w1, b1, w2, b2 = [floats(tensors[n]) for n in PROJ]
    z = rows @ w1.T + b1
    z = z / (1.0 + np.exp(-z))
    return z @ w2.T + b2

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--base', type=Path, required=True)
    p.add_argument('--customvoice-bf16', type=Path, required=True)
    p.add_argument('--customvoice-q8', type=Path, required=True)
    p.add_argument('--xvectors', type=Path, required=True)
    p.add_argument('--variant', choices=['xvector', 'graft'], required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    if a.output.exists() or a.output.with_suffix('.gguf.part').exists():
        raise SystemExit('Refusing to overwrite an existing export or partial file')
    paths = {'base': a.base, 'customvoice_bf16': a.customvoice_bf16,
             'customvoice_q8': a.customvoice_q8}
    readers = {k: gguf.GGUFReader(str(v)) for k,v in paths.items()}
    tables = {k: {t.name:t for t in r.tensors} for k,r in readers.items()}
    base, cv, q8 = [tables[k] for k in paths]
    for k,r in readers.items():
        assert val(r,'general.architecture') == 'qwen3-tts'
        assert val(r,'qwen3-tts.talker.embedding_length') == 2048
        assert val(r,'qwen3-tts.model_type') == ('base' if k == 'base' else 'custom_voice')
    assert cv[TEXT].tensor_type == base[TEXT].tensor_type == gguf.GGMLQuantizationType.BF16
    assert tuple(cv[CODEC].shape) == (2048,3072)
    for n in [TEXT,CODEC,*PROJ]: assert np.array_equal(cv[n].shape,base[n].shape)
    ref_reader = readers['customvoice_bf16']
    reserved = {key:val(ref_reader,key) for key in ref_reader.fields
                if key.startswith('qwen3-tts.codec.') and key.endswith('_id')}
    reserved['language_ids'] = val(ref_reader,'qwen3-tts.codec.language_ids')
    forbidden = set(reserved['language_ids']) | {v for k,v in reserved.items() if k != 'language_ids'}
    assert len(set(VOICE_ROWS.values())) == len(VOICE_ROWS)
    assert not (set(VOICE_ROWS.values()) & forbidden), 'Clone row collides with codec control/language'
    assert all(2048 <= row < 3072 for row in VOICE_ROWS.values())

    # BF16 source defines community normalization, even with Q8 backbone.
    cv_codec = floats(cv[CODEC])
    codec = floats(q8[CODEC]).copy()
    overrides = {}
    audit = {'status':'preparing', 'variant':a.variant, 'experimental':True,
        'semantics':'Community bare x-vector or WOVR/TPAD graft; no ICL/ref-codes, WDELTA, emotion steering, or fine-tuning',
        'source_revisions':{'runtime':'71ad93d591a2811f35db77e27c02acba091c9e9b',
            'community':'e56ec7e6eabbed608b13bfbd3fba431708b2077f',
            'gguf_python':'64d092c60db4b4ee45768476bd752f03fdcc98ea'},
        'sources':{k:{'path':str(v),'bytes':v.stat().st_size,'sha256':digest(v)} for k,v in paths.items()}}
    audit['speaker_id_validation'] = {'rows':VOICE_ROWS,'reserved_codec_ids':reserved,
        'collision':False,'primary':'k2so_primary'}
    print('Source hashes complete', flush=True)
    base_special = floats(base[TEXT], SPECIAL)
    cv_special = floats(cv[TEXT], SPECIAL)
    audit['special_rows'] = {'ids':SPECIAL,
        'base_custom_bf16_byte_equal':bool(np.array_equal(base[TEXT].data[SPECIAL],cv[TEXT].data[SPECIAL])),
        'base_custom_max_abs':float(np.max(np.abs(base_special-cv_special)))}
    if a.variant == 'graft':
        # WOVR stores exactly 2048 acoustic rows. Preserve all CV controls.
        codec[:2048] = floats(base[CODEC],slice(0,2048))
        # Controls use original BF16 CV values, avoiding extra interface quantization.
        codec[2048:] = cv_codec[2048:]
        overrides.update({n:(base[n].data,base[n].tensor_type) for n in PROJ})
        text = cv[TEXT].data.copy()
        text[SPECIAL] = base[TEXT].data[SPECIAL]
        overrides[TEXT] = (text,cv[TEXT].tensor_type)
        final_special = gguf.dequantize(text[SPECIAL],cv[TEXT].tensor_type)
        expected = project(base_special,base)
        observed = project(final_special,base)
        err = float(np.max(np.abs(expected-observed)))
        assert err == 0.0
        audit['tpad_validation'] = {'dtype':'numpy float32 CPU',
            'base_vs_derived_max_abs':err,'bit_equal_same_evaluator':bool(np.array_equal(expected,observed)),
            'base_projected_sha256':datahash(expected),
            'caveat':'Verifies algebraic input equality; does not assert cross-backend floating-point bit identity'}
    target_norm = float(np.linalg.norm(cv_codec[3061]))
    audit['speaker_normalization'] = {'target_row':3061,'target_source':'CustomVoice BF16',
        'target_norm':target_norm,'QWEN_SPK_SCALE':1.0,'voices':{}}
    for name,row in VOICE_ROWS.items():
        path = a.xvectors / (name+'.spk')
        vec = np.fromfile(path,dtype='<f4')
        assert vec.shape == (2048,) and np.isfinite(vec).all()
        norm = float(np.linalg.norm(vec))
        assert norm > 0.1 and target_norm > 0.1
        codec[row] = vec * np.float32(target_norm/norm)
        audit['speaker_normalization']['voices'][name] = {'path':str(path),'sha256':digest(path),
            'row':row,'raw_norm':norm,'scale':target_norm/norm,'final_norm':float(np.linalg.norm(codec[row]))}
    assert np.isfinite(codec).all()
    overrides[CODEC] = (codec,gguf.GGMLQuantizationType.F32)
    r = readers['customvoice_q8']
    original_names = val(r,'qwen3-tts.codec.speaker_names')
    original_ids = val(r,'qwen3-tts.codec.speaker_ids')
    original_dialects = val(r,'qwen3-tts.codec.speaker_dialects')
    # Remove the original Ryan name because its row is now cloned.
    keep = [(n,i,d) for n,i,d in zip(original_names,original_ids,original_dialects) if i not in VOICE_ROWS.values()]
    audit['speaker_id_validation']['removed_preset_names'] = [n for n,i in zip(original_names,original_ids) if i in VOICE_ROWS.values()]
    names = [x[0] for x in keep] + list(VOICE_ROWS)
    ids = [x[1] for x in keep] + list(VOICE_ROWS.values())
    dialects = [x[2] for x in keep] + ['']*len(VOICE_ROWS)
    changed_metadata = {'general.name':f'Qwen3-TTS-1.7B-K2SO-CustomVoice-{a.variant}-mixed-Q8-experimental',
        'qwen3-tts.codec.speaker_names':names,'qwen3-tts.codec.speaker_ids':ids,
        'qwen3-tts.codec.speaker_dialects':dialects}
    a.output.parent.mkdir(parents=True,exist_ok=True)
    partial = a.output.with_suffix('.gguf.part')
    writer = gguf.GGUFWriter(str(partial),'qwen3-tts')
    for key,f in r.fields.items():
        if key.startswith('GGUF.') or key == 'general.architecture': continue
        writer.add_key_value(key,changed_metadata.get(key,f.contents()),f.types[0],f.types[-1] if len(f.types)>1 else None)
    for t in r.tensors:
        arr,typ = overrides.get(t.name,(t.data,t.tensor_type))
        writer.add_tensor(t.name,arr,raw_dtype=typ)
    writer.write_header_to_file(); writer.write_kv_data_to_file(); writer.write_tensors_to_file(); writer.close()
    print('Export written; checking every tensor',flush=True)
    check = gguf.GGUFReader(str(partial))
    assert len(check.tensors) == len(r.tensors)
    verified = []
    for t in check.tensors:
        source = q8[t.name]
        want,typ = overrides.get(t.name,(source.data,source.tensor_type))
        assert t.tensor_type == typ and np.array_equal(t.shape,source.shape)
        assert np.array_equal(t.data,want),t.name
        if t.name in overrides: verified.append({'name':t.name,'dtype':typ.name,'sha256':datahash(t.data)})
    for key,want in changed_metadata.items(): assert val(check,key) == want
    os.rename(partial,a.output)
    audit.update(status='verified',output={'path':str(a.output),'bytes':a.output.stat().st_size,'sha256':digest(a.output)},
        changed_tensors=verified,unchanged_tensors_verified=len(r.tensors)-len(overrides),
        exporter_sha256=digest(Path(__file__)),precision_note='Q8 transformer/predictor backbone with F32 codec table; full graft also keeps BF16 text embedding and Base projection matrices',
        runtime_tested=False)
    report = a.output.with_suffix('.provenance.json')
    report.write_text(json.dumps(audit,indent=2)+'\n')
    print(report,flush=True)

if __name__ == '__main__': main()
