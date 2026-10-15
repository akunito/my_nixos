{ pkgs }:
# VarBERT (binsync/varbert_api 2.3.1, BSD-2; models from the authors' Dropbox, Ghidra-trained
# only — the IDA-trained ones are excluded, see mejoras.md M4) as `rea-varbert`, a JSON-lines
# worker. Pinned: sdist and both model archives by hash. The models ship as pickled
# pytorch_model.bin (+ training_args.bin): converted to safetensors here, inside the build
# sandbox (no network) with torch.load(weights_only=True), and the pickles are dropped.
let
  py = pkgs.python3.withPackages (ps: [ ps.torch ps.transformers ps.tqdm ps.safetensors ]);
  src = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/65/f7/833a542e08264c7904871fb9f4491fb4791b49d1a23fbf212291bc9905ff/varbert-2.3.1.tar.gz";
    hash = "sha256-rFfv6kB1SD6ctHNOMmIjF3mP6zXfXyV3vx07Zvq/0gM=";
  };
  pkgSrc = pkgs.runCommand "varbert-2.3.1-src" { } ''
    mkdir -p $out && tar -xzf ${src} -C $out --strip-components=1
  '';
  tgz = opt: url: hash: pkgs.fetchurl { inherit url hash; name = "varbert-ghidra-${opt}-function.tar.gz"; };
  model = opt: tgz: pkgs.runCommand "varbert-ghidra-${opt}" { nativeBuildInputs = [ py ]; } ''
    mkdir -p $TMPDIR/m $out/models/ghidra
    tar -xzf ${tgz} -C $TMPDIR/m
    d=$TMPDIR/m/Ghidra-${opt}-Function
    python3 -I - "$d/pytorch_model.bin" "$out/models/ghidra/model.safetensors" <<'EOF'
    import sys, torch
    from safetensors.torch import save_file
    sd = torch.load(sys.argv[1], map_location="cpu", weights_only=True)
    # tied embedding / lm-head weights share storage; safetensors needs separate tensors
    save_file({k: v.contiguous().clone() for k, v in sd.items()}, sys.argv[2], metadata={"format": "pt"})
    EOF
    for f in config.json vocab.json merges.txt tokenizer.json tokenizer_config.json special_tokens_map.json idx_to_word.json word_to_idx.json; do
      cp $d/$f $out/models/ghidra/
    done
  '';
  tgzO0 = tgz "O0" "https://www.dropbox.com/scl/fi/8xsmmlzypd45icn8csk6y/Ghidra-O0-Function.tar.gz?rlkey=1b92b9ejktoyewjztvo3ns8q1&dl=1" "sha256-ePWp5UTu/1l7hCq22JC8EMZkW/gOxFgVa9zynG65YW8=";
  tgzO2 = tgz "O2" "https://www.dropbox.com/scl/fi/x5ci28s0aw3i852kg9w1j/Ghidra-O2-Function.tar.gz?rlkey=wpe08afvxelcblgcqndrxmvtm&dl=1" "sha256-EqAk7ZNhk/T6rPm6b6ShnUFXstgh2U3/neJstzyfjUQ=";
  o0 = model "O0" tgzO0;
  o2 = model "O2" tgzO2;
in
# vendor: the Dropbox originals (no upstream hash, could vanish) + sdist + converted models.
(pkgs.writeShellScriptBin "rea-varbert" ''
  export VARBERT_O0=${o0} VARBERT_O2=${o2}
  export PYTHONPATH=${./stubs}:${pkgSrc}
  export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 TOKENIZERS_PARALLELISM=false
  exec ${py}/bin/python3 -I -c 'import sys; sys.path[:0] = sys.argv[1].split(":"); exec(open(sys.argv[2]).read())' "$PYTHONPATH" ${./runner.py}
'') // { vendor = [ src tgzO0 tgzO2 o0 o2 ]; }
