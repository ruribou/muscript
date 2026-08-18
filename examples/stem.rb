require_relative "../lib/muscript"

# muscriptの受け入れテスト第2号: 手持ちのステムが素材として鳴るか。
#
#   ruby examples/stem.rb                          # stems/ に置いたファイルを使う
#   ruby examples/stem.rb path/to/stems out.wav    # 置き場所と出力先を指定する
#
# 形式は問わない(WAV/AIFF/mp3/flac...)。デコードとリサンプルはffmpegの仕事なので
# `brew install ffmpeg` が要る。stems/ が空なら、デモ用の素材を自分で書き出してから読む。
stems_dir = ARGV[0] || File.expand_path("../stems", __dir__)
out_path  = ARGV[1] || File.expand_path("../out/stem.wav", __dir__)

# 手持ちのステムが無い人でもこの例が鳴るように、muscript自身の音で2本作る。
def demo_stems(dir)
  drums = Muscript.project "demo drums" do
    bpm 174
    track :drums do
      pattern bars: 2 do
        kick  "x---------x-----"
        snare "----x-------x---"
        hat   "x-x-x-x-x-x-x-x-"
      end
    end
  end

  bass = Muscript.project "demo bass" do
    bpm 174
    track :bass do
      synth :saw
      notes %w[E1 _ _ E1 _ _ G1 _] * 2, step: "1/8"
    end
  end

  [drums.render(File.join(dir, "demo-drums.wav")),
   bass.render(File.join(dir, "demo-bass.wav"))]
end

# 並び順でトラックの左右が決まるので、作り立てでも読み直しでも同じ順に並べる。
stems = Dir.glob(File.join(stems_dir, "*.{wav,aif,aiff,mp3,flac,m4a,ogg}")).sort
stems = demo_stems(stems_dir).sort if stems.empty?

song = Muscript.project "Stem Remix" do
  bpm 174

  stems.each_with_index do |path, i|
    track File.basename(path, ".*").to_sym do
      audio path
      gain(-4)
      pan(i.even? ? -0.25 : 0.25) # 左右に少しだけ広げる
    end
  end
end

song.render out_path
