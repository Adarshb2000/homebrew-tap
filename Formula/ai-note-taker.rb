class AiNoteTaker < Formula
  desc "Local AI meeting note-taker: on-device transcription, diarization, summaries"
  homepage "https://github.com/Adarshb2000/good-freaking-note-taker"
  url "https://github.com/Adarshb2000/good-freaking-note-taker/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "c1478542bc32cb1b9f912785e648e07b6fc0f8f1b9d446dcb4b32eb273b521f7"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: :sequoia
  depends_on "python@3.12"

  def install
    # Swift capture helper (needs Command Line Tools' swiftc). Keep the module
    # cache inside the buildpath so the install sandbox stays happy.
    ENV["CLANG_MODULE_CACHE_PATH"] = (buildpath/"module-cache").to_s
    system "bash", "helper/build.sh"

    # Self-contained venv at its final Cellar path (stable shebangs).
    system Formula["python@3.12"].opt_bin/"python3.12", "-m", "venv", libexec/"venv"
    system libexec/"venv/bin/pip", "install", "--no-cache-dir", "-r", "requirements.txt"

    # maturin-built extensions (tiktoken, tokenizers, ...) ship as dylibs with
    # no Mach-O header padding, so brew's install-name relocation fails on them.
    # Convert the standalone ones to bundles (the correct type for dlopen'd
    # Python extensions); inter-linked dylib chains like torchaudio are skipped.
    system libexec/"venv/bin/python3", "helper/relocate_extensions.py",
           (libexec/"venv/lib/python3.12/site-packages").to_s

    libexec.install "watcher.py", "pipeline.py", "mic_monitor.py", "helper"

    (bin/"ai-note-taker").write <<~EOS
      #!/bin/bash
      exec "#{libexec}/venv/bin/python3" "#{libexec}/watcher.py" "$@"
    EOS
  end

  def post_install
    # Brew's relocation rewrites torchaudio's @loader_path rpaths to opt/lib,
    # breaking its @rpath links into torch/lib. Re-add absolute rpaths so the
    # torch/torchaudio library web resolves again.
    sp = libexec/"venv/lib/python3.12/site-packages"
    Dir[sp/"torchaudio/lib/*.so"].each do |f|
      system "install_name_tool", "-add_rpath", (sp/"torch/lib").to_s, f
      system "install_name_tool", "-add_rpath", (sp/"torchaudio/lib").to_s, f
      system "codesign", "--force", "--sign", "-", f
    end
  end

  service do
    run [opt_bin/"ai-note-taker"]
    keep_alive true
    log_path var/"log/ai-note-taker.log"
    error_log_path var/"log/ai-note-taker.err.log"
  end

  def caveats
    <<~EOS
      Start it:
        ai-note-taker
      The first meeting capture prompts for System Audio Recording + Microphone
      permission for AudioTapHelper — Allow both.

      Speaker diarization needs a free Hugging Face token:
        1. Create a read token: https://huggingface.co/settings/tokens
        2. Accept the gated terms for pyannote/speaker-diarization-3.1
           and pyannote/segmentation-3.0
        3. echo 'HF_TOKEN=hf_...' > #{libexec}/.env

      Autostart at login:
        brew services start ai-note-taker

      Building the helper requires Xcode Command Line Tools (xcode-select --install).
      Models download automatically on the first meeting. Notes: ~/Desktop/MeetingNotes.
    EOS
  end

  test do
    system libexec/"venv/bin/python3", "-c",
         "import sys; sys.path.insert(0, '#{libexec}'); import mic_monitor, pipeline, watcher"
  end
end