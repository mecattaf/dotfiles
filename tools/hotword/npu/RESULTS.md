> Historical results. Experimental implementation removed on 2026-09-15;
> CPU Alexa is the supported path. Commands below document the past test.

# Scott Baker NPU wake detector on the Meteor Lake Zenbook

The existing detector executes successfully on Intel NPU3720 in the actual ASUS Zenbook Duo UX8406MA running NixOS. The mel stage remains CPU; embedding and classifier execute on NPU. No microphone listener, system service, kernel change or firmware change was introduced. The isolated runtime is reproducible in `tools/hotword/npu` in the dotfiles worktree.

The official Intel1.35 userspace compiler had to be colocated with the OpenVINO NPU plugin/core and selected through PLUGIN mode. The model and detector algorithm were preserved. OpenVINO2026.3.1, UMD/compiler1.35.0 and LevelZero1.32.0 are pinned. [Actual execution smoke receipt](results/execution.json).

Speed is the primary criterion. Corrected callback-latency results will be recorded separately from per-frame processing cost. The same Mycroft recording is used by the CPU comparator. The source WAV end is a reproducible reference, but not an independently verified phonetic endpoint. No functional cue is played by these saved-input harnesses.

The completed resource windows used the original frame-start replay convention. That supplies audio80ms early for real-time callback interpretation, so those wall timestamps are not end-to-end wake latency. Resource consumption and logical input coverage remain useful. [Complete receipt](results/resources.json).

| NPU negative-speech run | Steady CPU, percent of one core | Peak RSS including startup | Frame processing p95 | Detections |
|---|---:|---:|---:|---:|
| First60s | 6.237% | 204.07MB | 9.93ms | 0 |
| Second60s | 5.034% | 204.13MB | 8.37ms | 0 |

The original positive fixture repeated one upstream Mycroft utterance three times, with5s leading and3s trailing silence per repetition; all three were accepted. This is one recorded voice repeated, not three independent speakers or a household accuracy study. CPU/RSS are secondary to the current speed priority.

The original shared negative is generated speech containing user-reported bang artifacts. Only its first60s were repeated in each resource window. Neither microphone/PipeWire overhead nor acoustic cue onset is measured. Short temperature/RPM windows do not establish audible fan differences.

## Corrected latency result and paused comparison

The corrected runner supplied each chunk at its nominal end. Scott's default three-frame confirmation accepted all three repetitions at **30.885725, 39.845916 and 48.886316 seconds** after the replay began. The shared recording had 30 seconds of initial streamed silence; the source utterance file ended at30.952,39.904 and48.856 seconds. These correspond to file-end offsets of−66.275,−58.084 and+30.316 milliseconds. The exact phonetic endpoint is unverified, so these are not perceived-delay measurements. No cue was played. [Corrected timing receipt](results/latency.json).

The completed default-three run has54 condition samples at one-second intervals, including before and after completion. All recorded active-panel brightness values were zero and both DPMS states were On. This verifies the sampled condition; it does not observe changes between polls. [Display samples](results/display-default3.json).

During the subsequent single-frame run, brightness returned to400. The guard stopped its child before the first phrase. No single-frame speed result exists, and no brightness change or rerun was performed after the stop. The parent paused further client tests pending clarification. The earlier CPU batch also has an unverified brightness condition, so there is **no completed comparison under verified matching display conditions**. A descriptive157–161ms difference between the recorded CPU single-frame and NPU three-frame callbacks is consistent with the two extra80ms confirmation intervals; it does not establish a hardware speed difference. [Guard log](results/guard-stop.log).
