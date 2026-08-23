RSpec.describe Muscript::Edit do
  # 120BPM・サンプルレート100なら 1拍=50サンプル、1小節=200サンプル。
  # 値が位置そのものなので、どこを切り出したかが値で分かる。
  def bar = 200

  def source(bars: 4) = clip_of(ramp(bars * bar))
  def apply(edit, clip = source) = edit.apply(clip, bpm: 120)

  describe ".slice" do
    it "5小節目から8小節、を拍で憶える" do
      expect(described_class.slice(bars: 8, from: 5))
        .to eq described_class::Cut.new(from: 16.0, length: 32.0)
    end

    it "指定した小節から指定した長さだけ切り出す" do
      clip = apply(described_class.slice(bars: 2, from: 3))

      expect(clip.length).to eq 2 * bar
      expect(clip.left.first).to eq 2.0 * bar # 3小節目の頭
      expect(clip.left.last).to eq (4.0 * bar) - 1
    end

    it "from を省いたら頭から切る" do
      expect(apply(described_class.slice(bars: 1)).left).to eq ramp(bar)
    end

    it "拍でも切れる" do
      expect(apply(described_class.slice(beats: 2, from: 2)).length).to eq 100
    end

    it "左右を同じところで切る" do
      clip = apply(described_class.slice(bars: 1, from: 2), clip_of(ramp(4 * bar), ramp(4 * bar, from: 1000)))

      expect(clip.left.first).to eq 200.0
      expect(clip.right.first).to eq 1200.0
    end

    it "素材とサンプルレートは持ち回る" do
      clip = apply(described_class.slice(bars: 1))

      expect(clip.path).to eq "spec.wav"
      expect(clip.sample_rate).to eq 100
    end

    it "素材より後ろから切ろうとしたら、素材の長さを教えて落ちる" do
      expect { apply(described_class.slice(bars: 1, from: 9)) }
        .to raise_error(ArgumentError, "cannot start at bar 9: spec.wav is 4 bars at 120 BPM")
    end

    it "素材より長く切ろうとしたら、素材の長さを教えて落ちる" do
      expect { apply(described_class.slice(bars: 8, from: 3)) }
        .to raise_error(ArgumentError, "cannot cut 8 bars from bar 3: spec.wav is 4 bars at 120 BPM")
    end

    it "数サンプルの不足は黙って詰める（伸縮の丸めで1サンプルずれるため）" do
      clip = apply(described_class.slice(bars: 4), clip_of(ramp((4 * bar) - 2)))

      expect(clip.length).to eq (4 * bar) - 2
    end
  end

  describe ".trim" do
    it "頭を落として最後まで残す" do
      clip = apply(described_class.trim(from: 3))

      expect(clip.left.first).to eq 2.0 * bar
      expect(clip.length).to eq 2 * bar
    end

    it "to は「その小節の手前まで」（2小節目から6小節目の手前=4小節）" do
      clip = apply(described_class.trim(from: 2, to: 6), source(bars: 8))

      expect(clip.left.first).to eq 1.0 * bar
      expect(clip.length).to eq 4 * bar
    end

    it "何も言わなければ素材まるごと" do
      expect(apply(described_class.trim).length).to eq 4 * bar
    end

    it "to が from より前なら落とす" do
      expect { described_class.trim(from: 5, to: 3) }
        .to raise_error(ArgumentError, /trim to: 3 must come after from: 5/)
    end
  end

  describe ".loop" do
    it "times 回ぶん繰り返す" do
      clip = apply(described_class.loop(times: 3), clip_of(ramp(bar)))

      expect(clip.length).to eq 3 * bar
      expect(clip.left[bar, bar]).to eq ramp(bar)
      expect(clip.left[2 * bar, bar]).to eq ramp(bar)
    end

    it "小節ぶんになるまで繰り返して、端で切る" do
      clip = apply(described_class.loop(bars: 3), clip_of(ramp(2 * bar)))

      expect(clip.length).to eq 3 * bar
      expect(clip.left.last).to eq bar - 1.0 # 3周目の途中で切れている
    end

    it "素材より短い長さを指定したら、そこで切る" do
      expect(apply(described_class.loop(bars: 1), clip_of(ramp(4 * bar))).length).to eq bar
    end

    it "左右をずらさずに繰り返す" do
      clip = apply(described_class.loop(times: 2), clip_of(ramp(bar), ramp(bar, from: 1000)))

      expect(clip.left[bar]).to eq 0.0
      expect(clip.right[bar]).to eq 1000.0
    end

    it "回数と長さの両方は受け取らない" do
      expect { described_class.loop(times: 2, bars: 4) }
        .to raise_error(ArgumentError, /not both/)
    end

    it "回数は1以上の整数だけ" do
      [0, -1, 1.5, "4"].each do |bad|
        expect { described_class.loop(times: bad) }
          .to raise_error(ArgumentError, /integer >= 1/), "#{bad.inspect} が通ってしまった"
      end
    end

    it "回数も長さも無ければ、何を書けばいいか教えて落ちる" do
      expect { described_class.loop }.to raise_error(ArgumentError, /give bars: or beats:/)
    end
  end

  describe "組み合わせ" do
    it "切ってから繰り返す（書いた順に掛かる）" do
      edits = [described_class.slice(bars: 1, from: 2), described_class.loop(times: 4)]
      clip = edits.reduce(source) { |c, e| e.apply(c, bpm: 120) }

      expect(clip.length).to eq 4 * bar
      expect(clip.left.first).to eq 200.0
      expect(clip.left[bar]).to eq 200.0 # 2周目も同じところから
    end

    it "テンポが変われば同じ指定でも長さが変わる" do
      lengths = [120, 60].map { |bpm| described_class.slice(bars: 1).apply(clip_of(ramp(1000)), bpm:).length }

      expect(lengths).to eq [200, 400]
    end
  end
end
