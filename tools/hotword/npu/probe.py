import json,os,sys,traceback
import openvino as ov
r={'openvino':ov.__version__,'python':sys.version,'ld_library_path':os.environ.get('LD_LIBRARY_PATH'),'microphone_opened':False,'inference_run':False}
try:
 c=ov.Core();r['available_devices']=c.available_devices
 r['npu_properties']={}
 for k in ['FULL_DEVICE_NAME','NPU_DRIVER_VERSION','NPU_COMPILER_VERSION','NPU_COMPILER_TYPE','DEVICE_ARCHITECTURE','SUPPORTED_PROPERTIES']:
  try:r['npu_properties'][k]=str(c.get_property('NPU',k))
  except Exception as e:r['npu_properties'][k]={'error':str(e)}
except Exception:r['exception']=traceback.format_exc()
print(json.dumps(r,indent=2))
