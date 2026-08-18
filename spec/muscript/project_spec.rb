RSpec.describe Muscript::Project do
  subject(:project) { described_class.new("test song") }

  it "120BPMで始まる" do
    expect(project.bpm).to eq 120
    expect(project.tracks).to be_empty
  end

  describe "#samples_per_beat" do
    it "120BPMで1拍0.5秒ぶんのサンプル数になる" do
      expect(project.samples_per_beat).to eq 22_050.0
    end

    it "BPMを上げると1拍が短くなる（174BPM = DnB）" do
      project.bpm = 174
      expect(project.samples_per_beat).to be_within(0.01).of(15_206.90)
    end

    it "BPMを倍にすると1拍が半分になる" do
      project.bpm = 240
      expect(project.samples_per_beat).to eq 11_025.0
    end
  end

  describe "#render" do
    it "いちばん後ろのイベントの後に0.5秒の余韻を足した長さで書く" do
      project.add_track(track_with(Array.new(1000, 0.0), at: 4000))

      in_tmpdir do |dir|
        path = silent_render(project, File.join(dir, "a.wav"))
        expect(read_wav(path)[:left].length).to eq 5000 + (Muscript::SAMPLE_RATE * 0.5).to_i
      end
    end

    it "書いたパスを返す" do
      project.add_track(track_with([0.0]))

      in_tmpdir do |dir|
        path = File.join(dir, "a.wav")
        expect(silent_render(project, path)).to eq path
      end
    end

    it "トラックを足し合わせる" do
      project.add_track(track_with(Array.new(100, 0.2)))
      project.add_track(track_with(Array.new(100, 0.3)))

      in_tmpdir do |dir|
        wav = read_wav(silent_render(project, File.join(dir, "a.wav")))
        # 0.5 を等パワーパンで振り分けた値
        expect(wav[:left].first / 32_767.0).to be_within(0.001).of(0.5 * Math.sqrt(0.5))
        expect(wav[:right].first / 32_767.0).to be_within(0.001).of(0.5 * Math.sqrt(0.5))
      end
    end

    it "イベントの位置どおりに置く" do
      project.add_track(track_with(Array.new(10, 1.0), at: 1000))

      in_tmpdir do |dir|
        wav = read_wav(silent_render(project, File.join(dir, "a.wav")))
        expect(wav[:left][999]).to eq 0
        expect(wav[:left][1000]).not_to eq 0
        expect(wav[:left][1010]).to eq 0
      end
    end

    it "gainとpanを反映する" do
      track = track_with(Array.new(100, 1.0))
      track.gain_db = -6.0
      track.pan = -1.0
      project.add_track(track)

      in_tmpdir do |dir|
        wav = read_wav(silent_render(project, File.join(dir, "a.wav")))
        expect(wav[:left].first / 32_767.0).to be_within(0.005).of(0.5)
        expect(wav[:right].first).to eq 0
      end
    end

    it "0dBFSを超えたら-1dBFSまで下げる（クリップさせない）" do
      track = track_with(Array.new(100, 1.0))
      track.gain_db = 6.0
      project.add_track(track)

      in_tmpdir do |dir|
        wav = read_wav(silent_render(project, File.join(dir, "a.wav")))
        expect(peak_of(wav[:left], wav[:right])).to be_within(0.001).of(0.891)
      end
    end

    it "収まっている時は音量に触らない" do
      project.add_track(track_with(Array.new(100, 0.5)))

      in_tmpdir do |dir|
        wav = read_wav(silent_render(project, File.join(dir, "a.wav")))
        expect(peak_of(wav[:left])).to be_within(0.001).of(0.5 * Math.sqrt(0.5))
      end
    end

    it "トラックが無ければ余韻ぶんの無音を書く" do
      in_tmpdir do |dir|
        wav = read_wav(silent_render(project, File.join(dir, "a.wav")))
        expect(wav[:left].length).to eq (Muscript::SAMPLE_RATE * 0.5).to_i
        expect(wav[:left].uniq).to eq [0]
      end
    end

    it "曲名・トラック数・長さ・ピークを1行で報告する" do
      project.add_track(track_with(Array.new(100, 0.5)))

      in_tmpdir do |dir|
        path = File.join(dir, "a.wav")
        expect { project.render(path) }
          .to output(/\Atest song \| 1 tracks \| 0\.50s \| peak -9\.0 dBFS -> #{Regexp.escape(path)}\n\z/)
          .to_stdout
      end
    end

    it "音量を下げた時はそう言う" do
      track = track_with(Array.new(100, 1.0))
      track.gain_db = 6.0
      project.add_track(track)

      in_tmpdir do |dir|
        expect { project.render(File.join(dir, "a.wav")) }
          .to output(/peak 3\.0 dBFS \(normalized to -1dBFS\)/).to_stdout
      end
    end

    it "同じプロジェクトからは同じWAVを書く（決定論）" do
      project.bpm = 174
      project.add_track(track_with(Muscript::Synth.drum(:kick)))
      project.add_track(track_with(Muscript::Synth.tone(:saw, Muscript::Note.freq("E1"), 5000)))

      in_tmpdir do |dir|
        a = silent_render(project, File.join(dir, "a.wav"))
        b = silent_render(project, File.join(dir, "b.wav"))
        expect(File.binread(a)).to eq File.binread(b)
      end
    end
  end
end
