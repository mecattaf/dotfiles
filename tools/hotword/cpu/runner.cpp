#include <sherpa-onnx/c-api/c-api.h>
#include <nlohmann/json.hpp>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <vector>
using json=nlohmann::json;
using Clock=std::chrono::steady_clock;
double wall(){return std::chrono::duration<double>(Clock::now().time_since_epoch()).count();}
double cpu(){timespec ts{};clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&ts);return ts.tv_sec+ts.tv_nsec/1e9;}
double p95(std::vector<double> a){if(a.empty())return 0;std::sort(a.begin(),a.end());return a[std::min(a.size()-1,size_t(std::ceil(a.size()*.95)-1))];}
void emit(const json&j){std::cout<<j.dump()<<std::endl;}
int main(int argc,char**argv){
 const SherpaOnnxKeywordSpotter*spotter=nullptr;const SherpaOnnxOnlineStream*stream=nullptr;
 try{
  std::string mode="kws",dir,input,keywords;double seconds=60;bool paced=true;
  for(int i=1;i<argc;i++){
   std::string a=argv[i];if(a=="--unpaced"){paced=false;continue;}
   if(i+1>=argc)throw std::runtime_error("Missing argument value");std::string v=argv[++i];
   if(a=="--mode")mode=v;else if(a=="--model-dir")dir=v;else if(a=="--input")input=v;
   else if(a=="--keywords")keywords=v;else if(a=="--seconds")seconds=std::stod(v);else throw std::runtime_error("Unknown argument: "+a);
  }
  if(mode!="disabled"&&mode!="replay"&&mode!="kws")throw std::runtime_error("mode disabled/replay/kws");
  if(seconds<1||seconds>300)throw std::runtime_error("duration must be1..300seconds");
  std::ifstream pcm;if(mode!="disabled"){pcm.open(input,std::ios::binary);if(!pcm)throw std::runtime_error("Cannot open raw16kmonoS16 input");}
  double load_start=wall();
  std::string encoder=dir+"/encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx";
  std::string decoder=dir+"/decoder-epoch-13-avg-2-chunk-16-left-64.onnx";
  std::string joiner=dir+"/joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx";
  std::string tokens=dir+"/tokens.txt";
  if(mode=="kws"){
   SherpaOnnxKeywordSpotterConfig cfg{};cfg.feat_config.sample_rate=16000;cfg.feat_config.feature_dim=80;
   cfg.model_config.transducer.encoder=encoder.c_str();cfg.model_config.transducer.decoder=decoder.c_str();cfg.model_config.transducer.joiner=joiner.c_str();
   cfg.model_config.tokens=tokens.c_str();cfg.model_config.num_threads=1;cfg.model_config.provider="cpu";
   cfg.max_active_paths=4;cfg.num_trailing_blanks=1;cfg.keywords_score=1;cfg.keywords_threshold=.25;cfg.keywords_file=keywords.c_str();
   spotter=SherpaOnnxCreateKeywordSpotter(&cfg);if(!spotter)throw std::runtime_error("KeywordSpotter initialization failed");
   stream=SherpaOnnxCreateKeywordStream(spotter);if(!stream)throw std::runtime_error("Keyword stream initialization failed");
  }
  emit({{"type","ready"},{"pid",getpid()},{"mode",mode},{"model_load_seconds",wall()-load_start},{"threads",1},{"paced",paced},
        {"cadence_seconds",.08},{"model_chunk_seconds",.32},{"seconds",seconds},{"threshold",.25},{"max_active_paths",4}});
  constexpr int samples=1280;std::array<int16_t,samples>raw{};std::array<float,samples>audio{};
  std::vector<double>durations,decode_durations,lags,window_cpu;json events=json::array();
  const int frames=int(std::round(seconds/.08));double started=wall(),cpu_start=cpu(),last_wall=started,last_cpu=cpu_start;
  uint64_t checksum=0;int decode_calls=0,late_frames=0;struct rusage ru0{};getrusage(RUSAGE_SELF,&ru0);
  for(int frame=0;frame<frames;frame++){
   const double deadline=started+(frame+1)*.08;
   if(paced){timespec t{time_t(deadline),long((deadline-std::floor(deadline))*1e9)};while(clock_nanosleep(CLOCK_MONOTONIC,TIMER_ABSTIME,&t,nullptr)==EINTR){}}
   double began=wall();double lag=paced?std::max(0.,began-deadline):0;lags.push_back(lag);if(lag>.08)late_frames++;
   if(mode!="disabled"){
    pcm.read(reinterpret_cast<char*>(raw.data()),samples*2);auto bytes=pcm.gcount();
    if(bytes<samples*2){std::fill(reinterpret_cast<char*>(raw.data())+bytes,reinterpret_cast<char*>(raw.data())+samples*2,0);pcm.clear();pcm.seekg(0);}
    for(int j=0;j<samples;j++){audio[j]=raw[j]/32768.f;checksum+=uint16_t(raw[j]);}
   }
   if(spotter){
    SherpaOnnxOnlineStreamAcceptWaveform(stream,16000,audio.data(),samples);
    while(SherpaOnnxIsKeywordStreamReady(spotter,stream)){
     double ds=wall();SherpaOnnxDecodeKeywordStream(spotter,stream);decode_durations.push_back(wall()-ds);decode_calls++;
     const auto*result=SherpaOnnxGetKeywordResult(spotter,stream);
     if(result&&result->keyword&&result->keyword[0]){
      json e={{"type","keyword"},{"keyword",result->keyword},{"input_end_seconds",(frame+1)*.08},{"wall_since_ready_seconds",wall()-started},
              {"segment_start_seconds",result->start_time},{"timestamps",json::array()}};
      for(int n=0;n<result->count;n++)e["timestamps"].push_back(result->timestamps[n]);events.push_back(e);emit(e);SherpaOnnxResetKeywordStream(spotter,stream);
     }
     if(result)SherpaOnnxDestroyKeywordResult(result);
    }
   }
   durations.push_back(wall()-began);
   double now=wall();if(now-last_wall>=1 || frame==frames-1){double current=cpu(),share=(current-last_cpu)/(now-last_wall);window_cpu.push_back(share);
    emit({{"type","cpu_window"},{"wall_seconds",now-last_wall},{"cpu_seconds",current-last_cpu},{"one_core_fraction",share},{"elapsed",now-started}});last_wall=now;last_cpu=current;}
  }
  double elapsed=wall()-started,used=cpu()-cpu_start;struct rusage ru{};getrusage(RUSAGE_SELF,&ru);
  emit({{"type","summary"},{"mode",mode},{"wall_seconds",elapsed},{"audio_seconds",frames*.08},{"cpu_seconds",used},
        {"cpu_one_core_fraction",used/elapsed},{"cpu_one_second_p95",p95(window_cpu)},{"frame_processing_p95_ms",p95(durations)*1000},
        {"decode_call_p95_ms",p95(decode_durations)*1000},{"arrival_lag_p95_ms",p95(lags)*1000},{"arrival_lag_max_ms",*std::max_element(lags.begin(),lags.end())*1000},
        {"late_over80ms_frames",late_frames},{"decode_calls",decode_calls},{"max_rss_kib",ru.ru_maxrss},
        {"voluntary_context_switches",ru.ru_nvcsw-ru0.ru_nvcsw},{"involuntary_context_switches",ru.ru_nivcsw-ru0.ru_nivcsw},
        {"checksum",checksum},{"events",events},{"input_frames",frames},{"paced",paced}});
  if(stream)SherpaOnnxDestroyOnlineStream(stream);if(spotter)SherpaOnnxDestroyKeywordSpotter(spotter);return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<std::endl;if(stream)SherpaOnnxDestroyOnlineStream(stream);if(spotter)SherpaOnnxDestroyKeywordSpotter(spotter);return 1;}
}
