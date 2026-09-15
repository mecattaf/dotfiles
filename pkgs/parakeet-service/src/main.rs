//! Private, resident inference worker. The socket frontend owns capture and validation.
use parakeet_rs::{ExecutionConfig, ParakeetTDT, Transcriber};
use std::io::{self, BufRead, Write};
use std::time::Instant;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let model_path = std::env::args().nth(1).ok_or("model directory required")?;
    let config = ExecutionConfig::new().with_custom_configure(|builder| {
        // Refuse a missing/broken GPU provider instead of silently loading on CPU.
        Ok(builder.with_execution_providers([ort::ep::MIGraphX::default().build().error_on_failure()])?)
    });
    let started = Instant::now();
    let mut model = ParakeetTDT::from_pretrained(model_path, Some(config))?;
    println!("{}", serde_json::json!({"ready":true,"backend":"MIGraphX","load_seconds":started.elapsed().as_secs_f64()}));
    io::stdout().flush()?;
    for line in io::stdin().lock().lines() {
        let line = line?;
        let start = Instant::now();
        let result = (|| -> Result<String, Box<dyn std::error::Error>> {
            let path: String = serde_json::from_str(&line)?;
            let bytes = std::fs::read(path)?;
            if bytes.is_empty() || bytes.len() % 2 != 0 || bytes.len() > 16000 * 2 * 60 {
                return Err("expected 0–60 seconds of mono s16le at 16 kHz".into());
            }
            let samples = bytes.chunks_exact(2).map(|b| i16::from_le_bytes([b[0],b[1]]) as f32 / 32768.0).collect();
            Ok(model.transcribe_samples(samples, 16000, 1, None)?.text)
        })();
        let response = match result {
            Ok(text) => serde_json::json!({"text":text,"seconds":start.elapsed().as_secs_f64()}),
            Err(error) => serde_json::json!({"error":error.to_string()}),
        };
        println!("{response}");
        io::stdout().flush()?;
    }
    // Normal Rust teardown is intentional: lifecycle crashes must remain visible.
    Ok(())
}
