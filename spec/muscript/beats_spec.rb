RSpec.describe Muscript::Beats do
  describe ".length" do
    it "小節を拍に直す（4/4なので1小節=4拍）" do
      expect(described_class.length(bars: 8)).to eq 32.0
    end

    it "拍をそのまま受け取る" do
      expect(described_class.length(beats: 3)).to eq 3.0
    end

    it "小節と拍を足し合わせる" do
      expect(described_class.length(bars: 1, beats: 2)).to eq 6.0
    end

    it "小数の小節も受け取る（1.5小節=6拍）" do
      expect(described_class.length(bars: 1.5)).to eq 6.0
    end

    it "長さを言われなければ、何を書けばいいか教えて落ちる" do
      expect { described_class.length }.to raise_error(ArgumentError, /give bars: or beats:/)
    end

    it "0や負の長さを拒否する" do
      expect { described_class.length(bars: 0) }.to raise_error(ArgumentError, /must be positive/)
      expect { described_class.length(beats: -4) }.to raise_error(ArgumentError, /must be positive/)
    end

    it "数でないものを拒否する" do
      expect { described_class.length(bars: "8") }.to raise_error(ArgumentError, /bars must be a number/)
    end
  end

  describe ".position" do
    it "小節番号を1から数える（1小節目の頭=0拍）" do
      expect(described_class.position(1)).to eq 0.0
      expect(described_class.position(5)).to eq 16.0
    end

    it "小数の小節番号は拍の位置になる（5.5=5小節目の3拍目）" do
      expect(described_class.position(5.5)).to eq 18.0
    end

    it "0小節目を拒否する（1から数える）" do
      expect { described_class.position(0) }.to raise_error(ArgumentError, /bar numbers start at 1/)
    end
  end

  describe ".samples" do
    it "拍をテンポでサンプルに直す（120BPMの1拍=22050サンプル）" do
      expect(described_class.samples(1, bpm: 120)).to eq 22_050
      expect(described_class.samples(4, bpm: 120)).to eq 88_200
    end

    it "テンポが上がるとサンプル数は減る" do
      expect(described_class.samples(4, bpm: 174)).to eq 60_828
    end

    it "サンプルレートを渡せる" do
      expect(described_class.samples(2, bpm: 120, sample_rate: 100)).to eq 100
    end

    it "端数は四捨五入する（サンプルに直すのはここだけ）" do
      expect(described_class.samples(1, bpm: 174)).to eq 15_207 # 15206.9
    end

    it "0以下のテンポを拒否する" do
      expect { described_class.samples(1, bpm: 0) }.to raise_error(ArgumentError, /bpm must be positive/)
    end
  end

  describe ".bars" do
    it "拍を小節に戻す（エラーメッセージ用）" do
      expect(described_class.bars(32.0)).to eq 8.0
      expect(described_class.bars(2.0)).to eq 0.5
    end
  end
end
