#!/usr/bin/env python3
"""Bounded saved-WAV driver around unchanged upstream openWakeWord Model."""
import argparse, hashlib, json, math, pathlib, resource, time, wave
p=argparse.ArgumentParser()
p.add_argument('--models',type=pathlib.Path,required=True)
p.add_argument('--wav',type=pathlib.Path,required=True)
p.add_argument('--mode',choices=['disabled','replay','detector'],default='detector')
p.add_argument('--seconds',type=float,default=60)
p.add_argument('--unpaced',action='store_true')
a=p.parse_args()
if not 1<=a.seconds<=180:p.error('seconds must be 1..180')
with wave.open(str(a.wav)) as w:
 if (w.getnchannels(),w.getsampwidth(),w.getframerate())!=(1,2,16000):raise ValueError('need mono16k PCM16')
 pcm=w.readframes(w.getnframes())
if not pcm:raise ValueError('empty fixture')
load=time.monotonic();model=None;providers={};imports_seconds=0;session_init_seconds=0
if a.mode=='detector':
 import numpy as np
 import onnxruntime as ort
 from openwakeword.model import Model
 imports_seconds=time.monotonic()-load;session_start=time.monotonic()
 # Upstream initializes its feature ring from random noise; fix the seed for reproducibility.
 np.random.seed(42)
 model=Model(wakeword_models=[str(a.models/'hey_mycroft_v0.1.onnx')],melspec_model_path=str(a.models/'melspectrogram.onnx'),embedding_model_path=str(a.models/'embedding_model.onnx'),inference_framework='onnx',ncpu=1,enable_speex_noise_suppression=False,vad_threshold=0)
 providers={k:v.get_providers() for k,v in model.models.items()}
 providers.update(mel=model.preprocessor.melspec_model.get_providers(),embedding=model.preprocessor.embedding_model.get_providers())
 assert all(v==['CPUExecutionProvider'] for v in providers.values()),providers
 session_init_seconds=time.monotonic()-session_start
load_seconds=time.monotonic()-load
start=time.monotonic();c0=time.process_time();u0=resource.getrusage(resource.RUSAGE_SELF)
print(json.dumps(dict(event='ready',monotonic=start,mode=a.mode,model_load_seconds=load_seconds,imports_seconds=imports_seconds,session_init_seconds=session_init_seconds,providers=providers,ort_version=ort.__version__ if model else None,threshold=.5,refractory_seconds=2,ncpu=1,fixture_sha256=hashlib.sha256(a.wav.read_bytes()).hexdigest(),microphone_opened=False,paced=not a.unpaced,delivery='chunk is provided at its nominal end time')),flush=True)
frames=math.ceil(a.seconds/.08);events=[];work=[];lags=[];windows=[];last=(start,c0);maximum=0;last_event=-100
for frame in range(frames):
 deadline=start+(frame+1)*.08
 if not a.unpaced:time.sleep(max(0,deadline-time.monotonic()))
 t0=time.monotonic();lags.append(max(0,t0-deadline) if not a.unpaced else 0)
 offset=frame*2560%len(pcm);chunk=(pcm[offset:offset+2560]+pcm[:2560])[:2560]
 if model:
  score=float(model.predict(np.frombuffer(chunk,dtype=np.int16))['hey_mycroft_v0.1']);maximum=max(maximum,score)
  # Fixed event policy, without resetting upstream feature state or tuning from test labels.
  if score>=.5 and frame*.08-last_event>=2:
   last_event=frame*.08;e=dict(input_end_seconds=(frame+1)*.08,wall_since_ready_seconds=time.monotonic()-start,score=score);events.append(e);print(json.dumps(dict(event='detection',**e)),flush=True)
 elif a.mode=='replay': _=len(chunk)
 work.append(time.monotonic()-t0);now=time.monotonic()
 if now-last[0]>=1:
  cpu=time.process_time();windows.append((cpu-last[1])/(now-last[0]));last=(now,cpu)
if not a.unpaced:time.sleep(max(0,start+frames*.08-time.monotonic()))
wall=time.monotonic()-start;cpu=time.process_time()-c0;u1=resource.getrusage(resource.RUSAGE_SELF)
def p95(xs):return sorted(xs)[min(len(xs)-1,math.ceil(.95*len(xs))-1)] if xs else None
print(json.dumps(dict(event='summary',mode=a.mode,steady_wall_seconds=wall,audio_seconds=frames*.08,steady_cpu_seconds=cpu,steady_cpu_core_share=cpu/wall,steady_cpu_window_p95=p95(windows),frame_work_ms_p95=p95(work)*1000,deadline_lag_ms_p95=p95(lags)*1000,frames_late_over80ms=sum(x>.08 for x in lags),ru_maxrss_kib=u1.ru_maxrss,steady_voluntary_context_switches=u1.ru_nvcsw-u0.ru_nvcsw,steady_involuntary_context_switches=u1.ru_nivcsw-u0.ru_nivcsw,events=events,max_classifier_score=maximum,cpu_windows_core_share=windows)),flush=True)
