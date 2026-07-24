{
  python3Packages,
  writeShellApplication,
}:

let
  upstream = python3Packages.huggingface-hub;
in
writeShellApplication {
  name = "hf";

  # Keep the token out of the store and out of Hugging Face's mutable login
  # cache. agenix decrypts it under /run; an explicitly supplied HF_TOKEN still
  # wins, and HF_TOKEN_FILE exists so the isolated flake smoke can use a fixture.
  text = ''
    token_file="''${HF_TOKEN_FILE:-/run/agenix/huggingface-token}"
    if [[ ! -v HF_TOKEN && -r "$token_file" ]]; then
      HF_TOKEN="$(<"$token_file")"
      export HF_TOKEN
    fi

    exec ${upstream}/bin/hf "$@"
  '';

  passthru = {
    inherit upstream;
    version = upstream.version;
  };

  meta = upstream.meta // {
    description = "Hugging Face Hub CLI with runtime-only agenix authentication";
    mainProgram = "hf";
  };
}
