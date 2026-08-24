require_relative "../lib/muscript"

# muscriptの受け入れテスト第5号: 曲に構造を書く。
# イントロ(ドラム無し) → ドロップ(全トラック)の2部構成。
#
#   ruby examples/arrange.rb            # out/arrange.wav に書く
#   ruby examples/arrange.rb out.wav    # 出力先を指定する
#
# 内蔵音源だけで鳴るので、ffmpegもrubberbandも要らない。
out_path = ARGV[0] || File.expand_path("../out/arrange.wav", __dir__)

BASS = %w[E1 _ _ E1 _ _ G1 _] * 2 + %w[A1 _ _ A1 _ _ B1 _] * 2 # 4小節のフレーズ

song = Muscript.project "Arrange Test" do
  bpm 174

  # 曲の構造。書いた順に並ぶので、ドロップは9小節目から始まる。
  section :intro, bars: 8
  section :drop,  bars: 16

  # パッド: イントロだけ。2小節にひと音。
  track :pad do
    synth :sine
    gain(-10)
    at :intro
    notes %w[E3 B3 G3 B3], step: "2/1"
  end

  # フィル: イントロの最後の1小節だけスネアロール(ドロップの合図)。
  track :fill do
    gain(-6)
    at :intro, bar: 8
    pattern bars: 1 do
      snare "xxxxxxxxxxxxxxxx"
    end
  end

  # ドラム: ドロップから。bars: を書かないので、ドロップの16小節を埋める。
  # セクションを伸ばせば、ここも一緒に伸びる。
  track :drums do
    at :drop
    pattern do
      kick  "x---------x-----"
      snare "----x-------x---"
      hat   "x-x-x-x-x-x-x-x-"
    end
  end

  # ベース: ドロップから。4小節のフレーズを4回で16小節。
  track :bass do
    synth :saw
    gain(-8)
    at :drop
    notes BASS * 4, step: "1/8"
  end
end

song.render out_path
