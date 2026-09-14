"""Paced saved-fixture runner for Scott's unchanged wake detector; never captures audio."""
import argparse,hashlib,json,math,os,pathlib,resource,sys,time,wave
p=argparse.ArgumentParser();p.add_argument('--models',required=True);p.add_argument('--wav',required=True);p.add_argument('--seconds',type=float,default=45);p.add_argument('--consecutive',type=int,choices=[1,2,3],default=3);p.add_argument('--mode',choices=['disabled','replay','npu'],default='npu');a=p.parse_args()
if not 1<=a.seconds<=180:p.error('seconds must be1..180')
with wave.open(a.wav) as w:
 if (w.getnchannels(),w.getsampwidth(),w.getframerate())!=(1,2,16000):raise ValueError('need mono16kPCM16')
 pcm=w.readframes(w.getnframes())
r={'mode':a.mode,'fixture':a.wav,'fixture_sha256':hashlib.sha256(pathlib.Path(a.wav).read_bytes()).hexdigest(),'fixture_seconds':len(pcm)/32000,'requested_seconds':a.seconds,'pcm_looped':a.seconds>len(pcm)/32000,'microphone_opened':False,'cadence':'frame-end available before processing','consecutive':a.consecutive}
d=None;events=[];score_max=None
if a.mode=='npu':
 import numpy as np
 import openvino as ov
 import wakeword
 realcore=ov.Core
 class ConfiguredCore(realcore):
  def __init__(self):
   super().__init__();self.set_property('CPU',{'INFERENCE_NUM_THREADS':1,'NUM_STREAMS':1});self.set_property('NPU',{'COMPILATION_NUM_THREADS':1,'NPU_COMPILER_TYPE':'PLUGIN'})
 wakeword.ov.Core=ConfiguredCore
 d=wakeword.WakeWordDetector(a.models,npu_device='NPU',consecutive=a.consecutive);r['openvino']=ov.__version__;r['execution_devices']={'mel':d._melspec.get_property('EXECUTION_DEVICES'),'embedding':d._embed.get_property('EXECUTION_DEVICES'),'classifiers':{n:c[0].get_property('EXECUTION_DEVICES') for n,c in d._classifiers.items()}}
 assert r['execution_devices']['embedding']=='NPU'
 original=d._classify
 def classify():
  global score_max
  v=original();score_max=max(score_max if score_max is not None else v,v);return v
 d._classify=classify
print(json.dumps({'event':'ready','monotonic':time.monotonic(),**r}),flush=True)
frames=math.ceil(a.seconds/.08);total_pcm=pcm*(math.ceil(frames*2560/len(pcm)));samples=[];lags=[];start=time.monotonic();cpu0=time.process_time();usage0=resource.getrusage(resource.RUSAGE_SELF);windows=[];last=(start,cpu0)
for frame in range(frames):
 deadline=start+(frame+1)*.08;time.sleep(max(0,deadline-time.monotonic()));t0=time.monotonic();lags.append(max(0,t0-deadline));chunk=total_pcm[frame*2560:(frame+1)*2560]
 if a.mode=='npu':
  score=d.process(np.frombuffer(chunk,dtype=np.int16))
  if score is not None:
   e={'frame':frame,'consumed_audio_end_seconds':(frame+1)*.08,'callback_wall_seconds_since_ready':time.monotonic()-start,'processing_until_callback_seconds':time.monotonic()-t0,'score':score};events.append(e);print(json.dumps({'event':'detection',**e}),flush=True);d.reset()
 elif a.mode=='replay':_ = len(chunk)
 samples.append(time.monotonic()-t0)
 now=time.monotonic()
 if now-last[0]>=1:
  cpu=time.process_time();windows.append((cpu-last[1])/(now-last[0]));last=(now,cpu)
time.sleep(max(0,start+frames*.08-time.monotonic()));elapsed=time.monotonic()-start;cpu=time.process_time()-cpu0;usage1=resource.getrusage(resource.RUSAGE_SELF)
def p95(v):return sorted(v)[min(len(v)-1,math.ceil(.95*len(v))-1)] if v else None
r.update(event='summary',steady_wall_seconds=elapsed,steady_cpu_seconds=cpu,steady_cpu_core_share=cpu/elapsed,steady_cpu_window_p95=p95(windows),frame_work_ms_p95=p95(samples)*1000,frame_work_ms_mean=sum(samples)/len(samples)*1000,deadline_lag_ms_p95=p95(lags)*1000,frames_late_over80ms=sum(t>.08 for t in lags),ru_maxrss_kib=usage1.ru_maxrss,steady_voluntary_context_switches=usage1.ru_nvcsw-usage0.ru_nvcsw,steady_involuntary_context_switches=usage1.ru_nivcsw-usage0.ru_nivcsw,events=events,max_classifier_score=score_max,ready_monotonic=start,frame_work_seconds=samples,frame_deadline_lag_seconds=lags,cpu_windows_core_share=windows)
print(json.dumps(r),flush=True)
