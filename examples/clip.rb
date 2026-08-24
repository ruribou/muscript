require_relative "../lib/muscript"

# muscriptの受け入れテスト第4号: 素材の一部を切り出して、繰り返して並べる。
#
#   ruby examples/clip.rb                          # stems/ のデモ素材を使う
#   ruby examples/clip.rb path/to/stems out.wav    # 置き場所と出力先を指定する
#
# デコードはffmpegに任せるので `brew install ffmpeg` が要る。
# 素材も曲も174BPMなので伸縮は起きない(rubberbandは使わない)。
#
# 素材のテンポはファイル名の末尾の数字で表している(demo-phrase-174.wav なら174BPM)。
BPM = 174
PHRASE = "demo-phrase-174.wav" # 12小節。1小節ごとに音が上がっていく
DRUMS  = "demo-drums-174.wav"  # 4小節のループ

# 1小節に1音。どこを切り出したかが耳でも数字でも分かるように、小節ごとに音を変えてある。
SCALE = %w[C3 D3 E3 G3 A3 C4 D4 E4 G4 A4 C5 D5].freeze

stems_dir = ARGV[0] || File.expand_path("../stems", __dir__)
out_path  = ARGV[1] || File.expand_path("../out/clip.wav", __dir__)

# 手持ちの素材が無い人でもこの例が鳴るように、muscript自身の音で2本書き出す。
def ensure_stem(dir, file, bars:, &block)
  path = File.join(dir, file)
  return path if File.file?(path)

  Muscript.project(File.basename(file, ".*"), &block).render(path)
  bars_only(path, bars:)
end

# render は最後に余韻を0.5秒足す。切ったり繰り返したりする素材はそれだと繋がらないので、
# 小節ぴったりにしてから置く(DSLの slice と同じ Edit を、ファイルに対して使っている)。
def bars_only(path, bars:)
  clip = Muscript::Edit.slice(bars:).apply(Muscript::Audio.load(path), bpm: BPM)
  Muscript::Wav.write(path, clip.left, clip.right)
end

phrase_path = ensure_stem(stems_dir, PHRASE, bars: SCALE.length) do
  bpm BPM
  track :phrase do
    synth :sine
    notes SCALE, step: "1/1" # 1音 = 1小節
  end
end

drums_path = ensure_stem(stems_dir, DRUMS, bars: 4) do
  bpm BPM
  track :drums do
    pattern bars: 4 do
      kick  "x-------x-------"
      snare "----x-------x---"
      hat   "x-x-x-x-x-x-x-x-"
    end
  end
end

song = Muscript.project "Clip Test" do
  bpm BPM

  # 12小節の素材から、5小節目からの8小節だけを取り出して4回鳴らす(= 32小節)。
  track :phrase do
    audio phrase_path, bpm: BPM
    slice bars: 8, from: 5
    loop times: 4
    gain(-3)
  end

  # ドラムは頭の2小節だけを使い、曲の長さぶん敷き詰める。
  track :drums do
    audio drums_path, bpm: BPM
    trim from: 1, to: 3 # 1小節目から3小節目の手前まで = 2小節
    loop bars: 32
    gain(-6)
  end
end

song.render out_path
