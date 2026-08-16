require_relative "../lib/muscript"

# muscriptの受け入れテスト第1号: DnBの2小節ループが音になるか。
song = Muscript.project "Hello, DnB" do
  bpm 174

  track :drums do
    pattern bars: 4 do
      kick  "x---------x-----"
      snare "----x-------x---"
      hat   "x-x-x-x-x-x-x-x-"
    end
  end

  track :bass do
    synth :saw
    gain(-8)
    notes %w[E1 _ _ E1 _ _ G1 _] * 2 + %w[A1 _ _ A1 _ _ B1 _] * 2, step: "1/8"
  end
end

song.render File.expand_path("../out/hello.wav", __dir__)
