require "open3"

# 「BPMの違うループ2本が174で揃って鳴る」の受け入れテスト。
# 素材の長さがバラバラでも、プロジェクトのBPMに合わせたあとは同じ小節数=同じ長さになる。
RSpec.describe "examples/warp.rb", :ffmpeg, :rubberband do
  let(:repo_root) { File.expand_path("../..", __dir__) }
  let(:project_bpm) { 174 }
  let(:bars) { 4 }
  # 例が書き出すデモ素材と、そのもとのテンポ(ファイル名の末尾がそのまま素材のBPM)。
  let(:loops) { { "demo-break-140.wav" => 140, "demo-bass-90.wav" => 90 } }

  # 例は「素材の置き場所」と「出力先」を引数で受け取れる。中間WAVのキャッシュも外に逃がす。
  def run_example(stems_dir, out_path, cache_dir: File.join(stems_dir, "cache"), rubberband: nil)
    env = { "MUSCRIPT_CACHE_DIR" => cache_dir }
    env["MUSCRIPT_RUBBERBAND"] = rubberband if rubberband
    out, err, status = Open3.capture3(env, "ruby", "examples/warp.rb", stems_dir, out_path, chdir: repo_root)
    raise "examples/warp.rb failed: #{err}" unless status.success?

    [out, err]
  end

  # 小節数 × 拍 ÷ BPM。この数字に素材が揃うことが、この例の主張そのもの。
  def frames_for(bpm) = (bars * 4 * 60.0 / bpm * Muscript::SAMPLE_RATE).round

  it "テンポの違う2本を174に揃えて1本にまとめる" do
    in_tmpdir do |dir|
      out_path = File.join(dir, "mix", "warp.wav")
      out, err = run_example(dir, out_path)

      expect(err).to be_empty
      expect(out).to match(/^Warp Test \| 2 tracks \| .+ -> #{Regexp.escape(out_path)}$/)

      wav = read_wav(out_path)
      expect(wav[:channels]).to eq 2
      expect(wav[:sample_rate]).to eq 44_100
      # 174BPMの4小節 + 余韻0.5秒。長い方の素材(90BPMで10.7秒)に引きずられていない
      expect(wav[:left].length).to eq frames_for(project_bpm) + (Muscript::SAMPLE_RATE * 0.5).to_i
      expect(peak_of(wav[:left], wav[:right])).to be > 0.1 # 無音ではない
    end
  end

  it "書き出すデモ素材は、もとのテンポのまま長さが違う（揃えたのはwarp）" do
    in_tmpdir do |dir|
      run_example(dir, File.join(dir, "mix", "warp.wav"))

      lengths = loops.map { |file, bpm| [Muscript::Audio.load(File.join(dir, file)).length, frames_for(bpm)] }
      expect(lengths.map(&:first)).to eq lengths.map(&:last)
      expect(lengths.map(&:first).uniq.length).to eq 2 # 素材の時点では長さが違う
    end
  end

  it "揃えたあとのステムは174のグリッドに乗る" do
    in_tmpdir do |dir|
      run_example(dir, File.join(dir, "mix", "warp.wav"))

      # projectブロックの中はDSLのselfになるので、必要なものはローカルに退避してから渡す。
      stems, target = loops, project_bpm
      song = Muscript.project("check") do
        bpm target
        stems.each do |file, source_bpm|
          track(file.to_sym) { audio File.join(dir, file), bpm: source_bpm }
        end
      end

      lengths = song.tracks.map { |t| t.events.first[:buf].length }
      expect(lengths).to eq [frames_for(project_bpm)] * 2
    end
  end

  it "ベースは半音+2でDからEに上がっている" do
    in_tmpdir do |dir|
      out_path = File.join(dir, "mix", "warp.wav")
      run_example(dir, out_path)
      left = read_wav(out_path)[:left].map { |s| s / 32_767.0 }

      # 素材はD1とF1のベースライン。+2半音でE1とG1になっているはず。
      expect(amplitude_at(left, Muscript::Note.freq("E2"))).to be > amplitude_at(left, Muscript::Note.freq("D2")) * 3
      expect(amplitude_at(left, Muscript::Note.freq("E1"))).to be > amplitude_at(left, Muscript::Note.freq("D1"))
    end
  end

  it "同じ素材からは同じWAVを書く（決定論）" do
    in_tmpdir do |dir|
      a = File.join(dir, "mix", "a.wav")
      b = File.join(dir, "mix", "b.wav")
      run_example(dir, a)
      run_example(dir, b)

      expect(File.binread(a)).to eq File.binread(b)
    end
  end

  it "二度目はキャッシュから読む（rubberbandを呼ばずに鳴る）" do
    in_tmpdir do |dir|
      cache = File.join(dir, "cache")
      run_example(dir, File.join(dir, "mix", "a.wav"), cache_dir: cache)
      expect(Dir.glob(File.join(cache, "warp", "*.wav")).length).to eq 2

      # 呼ばれたら落ちる偽物に差し替える。版だけ本物と同じにして、キャッシュを当てる。
      fake = fake_rubberband(dir, version: Muscript::Warp.version)
      out, = run_example(dir, File.join(dir, "mix", "b.wav"), cache_dir: cache, rubberband: fake)

      expect(out).to match(/Warp Test \| 2 tracks \|/)
      expect(File.binread(File.join(dir, "mix", "a.wav")))
        .to eq File.binread(File.join(dir, "mix", "b.wav"))
    end
  end
end
