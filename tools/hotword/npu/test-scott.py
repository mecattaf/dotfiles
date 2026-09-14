"""Existing Scott detector compatibility smoke test; no microphone or model downloads."""
import argparse,hashlib,json,logging,pathlib,sys,time,traceback
import numpy as np
import openvino as ov
import wakeword
p=argparse.ArgumentParser();p.add_argument('--models',required=True);p.add_argument('--device',default='NPU');p.add_argument('--output',required=True);p.add_argument('--compiler',choices=['DRIVER','PLUGIN'],default='DRIVER');a=p.parse_args()
logging.basicConfig(level=logging.INFO)
realcore=ov.Core
class ConfiguredCore(realcore):
 def __init__(self):
  super().__init__();self.set_property('CPU',{'INFERENCE_NUM_THREADS':1,'NUM_STREAMS':1});self.set_property('NPU',{'COMPILATION_NUM_THREADS':1,'NPU_COMPILER_TYPE':a.compiler})
wakeword.ov.Core=ConfiguredCore
r={'device_requested':a.device,'compiler_requested':a.compiler,'openvino':ov.__version__,'mic_opened':False,'fixture':'generated digital silence:32 x80ms chunks, then reset and repeat','cpu_inference_threads':1,'model_sha256':{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in pathlib.Path(a.models).glob('*.onnx')}}
try:
 d=wakeword.WakeWordDetector(a.models,npu_device=a.device)
 r['execution_devices']={'mel':d._melspec.get_property('EXECUTION_DEVICES'),'embedding':d._embed.get_property('EXECUTION_DEVICES'),'classifiers':{n:c[0].get_property('EXECUTION_DEVICES') for n,c in d._classifiers.items()}}
 if a.device=='NPU':assert 'NPU' in r['execution_devices']['embedding']
 events=[]
 for cycle in range(2):
  d.reset()
  for i in range(32):
   score=d.process(np.zeros(1280,dtype=np.int16))
   if score is not None:events.append({'cycle':cycle,'frame':i,'score':score})
 r.update(status='passed_execution',silence_events=events,quality_claim='None: silence smoke test is not wake recall/false-positive validation')
except Exception:r.update(status='failed',exception=traceback.format_exc())
pathlib.Path(a.output).write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2));sys.exit(0 if r['status']=='passed_execution' else 1)
