require "open3"

# muscriptの受け入れテストは「音が鳴る例」であり続ける。
# ここはその例（examples/）が今日も鳴ることを確かめる場所。
RSpec.describe "examples/hello.rb" do
  let(:repo_root) { File.expand_path("../..", __dir__) }

  # READMEに載っているコードそのまま。ここが壊れたらREADMEが嘘になる。
  def hello_song
    Muscript.project "Hello, DnB" do
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
  end

  it "174BPMで4小節のループを組み立てる" do
    song = hello_song

    expect(song.bpm).to eq 174
    expect(song.tracks.map(&:name)).to eq %i[drums bass]
    expect(song.tracks.first.events.length).to eq (2 + 2 + 8) * 4 # kick/snare/hat × 4小節
    expect(song.tracks.last.events.length).to eq 12               # 休符以外のベース音
  end

  it "5.91秒のWAVになる" do
    in_tmpdir do |dir|
      wav = read_wav(silent_render(hello_song, File.join(dir, "hello.wav")))

      expect(wav[:left].length / wav[:sample_rate].to_f).to be_within(0.01).of(5.91)
      expect(wav[:channels]).to eq 2
      expect(wav[:bits]).to eq 16
    end
  end

  it "何度レンダリングしても同じWAVになる" do
    in_tmpdir do |dir|
      a = silent_render(hello_song, File.join(dir, "a.wav"))
      b = silent_render(hello_song, File.join(dir, "b.wav"))

      expect(File.binread(a)).to eq File.binread(b)
    end
  end

  it "無音ではない（実際に音が入っている）" do
    in_tmpdir do |dir|
      wav = read_wav(silent_render(hello_song, File.join(dir, "hello.wav")))

      expect(peak_of(wav[:left], wav[:right])).to be_within(0.001).of(0.891)
      expect(wav[:left].count { |s| s.abs > 1000 }).to be > 10_000
    end
  end

  it "`ruby examples/hello.rb` が最後まで走る" do
    out, err, status = Open3.capture3("ruby", "examples/hello.rb", chdir: repo_root)

    expect(err).to be_empty
    expect(status).to be_success
    expect(out).to match(/\AHello, DnB \| 2 tracks \| 5\.91s \| peak .+ -> .+hello\.wav\n\z/)
  end
end
