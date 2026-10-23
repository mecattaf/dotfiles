let
  policy = builtins.fromJSON (builtins.readFile ../pkgs/local-ai-monthly/sources.json);
in
policy
// {
  inference = policy.inference // {
    url = (import ./local-model.nix).endpoint;
  };
}
