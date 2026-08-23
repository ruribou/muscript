require_relative "../lib/muscript"

# muscriptの受け入れテスト第3号: BPMの違うループ2本を、プロジェクトのテンポで揃えて鳴らす。
#
#   ruby examples/warp.rb                          # stems/ のデモ素材を使う
#   ruby examples/warp.rb path/to/stems out.wav    # 置き場所と出力先を指定する
#
# 伸縮とピッチシフトは rubberband CLI(R3エンジン)にシェルアウトするので
# `brew install ffmpeg rubberband` が要る。
#
# 素材のテンポはファイル名の末尾の数字で表している(demo-break-140.wav なら140BPM)。
# 同じ名前で自分のループを置けば、そのままこの例で鳴らせる。
stems_dir = ARGV[0] || File.expand_path("../stems", __dir__)
out_path  = ARGV[1] || File.expand_path("../out/warp.wav", __dir__)

BREAK = "demo-break-140.wav" # 140BPMのブレイク
BASS  = "demo-bass-90.wav"   # 90BPMのベース(Dキー)

def source_bpm(file) = File.basename(file, ".*")[/-(\d+)\z/, 1].to_i

# 手持ちのループが無い人でもこの例が鳴るように、muscript自身の音で2本書き出す。
def ensure_loop(dir, file, bars:, &block)
  path = File.join(dir, file)
  return path if File.file?(path)

  Muscript.project(File.basename(file, ".*"), &block).render(path)
  trim(path, bars:, bpm: source_bpm(file))
end

# render は最後に余韻を0.5秒足す。ループとして使う素材はそれだと繋がらないので、
# 小節ぴったりで切っておく(クリップのトリムそのものは #4 で入る)。
def trim(path, bars:, bpm:)
  clip = Muscript::Audio.load(path)
  frames = (bars * 4 * 60.0 / bpm * Muscript::SAMPLE_RATE).round
  Muscript::Wav.write(path, clip.left[0, frames], clip.right[0, frames])
end

break_path = ensure_loop(stems_dir, BREAK, bars: 4) do
  bpm 140
  track :drums do
    pattern bars: 4 do
      kick  "x-------x-------"
      snare "----x-------x---"
      hat   "x-x-x-x-x-x-x-x-"
    end
  end
end

bass_path = ensure_loop(stems_dir, BASS, bars: 4) do
  bpm 90
  track :bass do
    synth :saw
    notes %w[D1 _ _ D1 _ _ F1 _] * 4, step: "1/8"
  end
end

# 140BPMと90BPM。素材のテンポはバラバラでも、プロジェクトのBPMに揃えて鳴らす。
song = Muscript.project "Warp Test" do
  bpm 174

  track :break do
    audio break_path, bpm: source_bpm(BREAK) # 140 -> 174
    gain(-3)
  end

  track :bass do
    audio bass_path, bpm: source_bpm(BASS) # 90 -> 174
    transpose 2                            # 素材はDキー、曲はEキーなので半音+2
    gain(-6)
  end
end

song.render out_path
