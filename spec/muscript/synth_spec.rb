RSpec.describe Muscript::Synth do
  describe ".tone" do
    it "頼んだサンプル数だけ返す" do
      expect(described_class.tone(:sine, 440.0, 500).length).to eq 500
    end

    it "sineは-1.0..1.0に収まる" do
      buf = described_class.tone(:sine, 220.0, 4410)
      expect(buf.min).to be >= -1.0
      expect(buf.max).to be <= 1.0
    end

    it "sineは指定した周波数で鳴る" do
      buf = described_class.tone(:sine, 440.0, 22_050)
      expect(amplitude_at(buf, 440.0)).to be > 0.5
      expect(amplitude_at(buf, 660.0)).to be < 0.05
    end

    it "sawは倍音を持つ（sineは持たない）" do
      freq = 110.0
      saw  = described_class.tone(:saw, freq, 22_050)
      sine = described_class.tone(:sine, freq, 22_050)

      expect(amplitude_at(saw, freq * 2)).to be > amplitude_at(sine, freq * 2) * 10
      expect(amplitude_at(saw, freq * 3)).to be > 0.05
    end

    it "sawの倍音は基音より小さい（1/kで減る）" do
      buf = described_class.tone(:saw, 110.0, 22_050)
      fundamental = amplitude_at(buf, 110.0)
      expect(amplitude_at(buf, 220.0)).to be_within(fundamental * 0.15).of(fundamental / 2)
    end

    it "ナイキストを超える倍音は足さない（エイリアス防止）" do
      # 5kHzならsawの倍音は4本まで（12本ぶん足すと折り返す）
      buf = described_class.tone(:saw, 5000.0, 4410)
      expect(buf.length).to eq 4410
      expect(buf.max).to be <= 1.0
    end

    it "同じ引数からは同じ波形を返す" do
      expect(described_class.tone(:saw, 82.41, 2000))
        .to eq described_class.tone(:saw, 82.41, 2000)
    end

    it "知らない波形を拒否する" do
      expect { described_class.tone(:supersaw, 440.0, 100) }
        .to raise_error(ArgumentError, /unknown synth shape/)
    end
  end

  describe ".envelope!" do
    it "頭と尻を0から始めて0で終わらせる（クリックノイズ防止）" do
      buf = described_class.envelope!(Array.new(44_100, 1.0))
      expect(buf.first).to eq 0.0
      expect(buf.last).to eq 0.0
      expect(buf[Muscript::Synth::ATTACK_SAMPLES]).to be_within(1e-9).of(1.0)
    end

    it "アタックは単調に立ち上がる" do
      buf = described_class.envelope!(Array.new(44_100, 1.0))
      head = buf[0, Muscript::Synth::ATTACK_SAMPLES]
      expect(head).to eq head.sort
    end

    it "エンベロープより短いバッファでも壊れない" do
      buf = described_class.envelope!(Array.new(10, 1.0))
      expect(buf.length).to eq 10
      expect(buf.first).to eq 0.0
      expect(buf.last).to eq 0.0
    end

    it "破壊的に書き換え、同じ配列を返す" do
      buf = Array.new(1000, 1.0)
      expect(described_class.envelope!(buf)).to be buf
    end
  end

  describe ".drum" do
    it "kick / snare / hat を鳴らす" do
      %i[kick snare hat].each do |name|
        expect(described_class.drum(name).length).to be > 1000
      end
    end

    it "知らないドラムを拒否する" do
      expect { described_class.drum(:cowbell) }.to raise_error(ArgumentError, /unknown drum/)
    end

    it "同じバッファをキャッシュして返す" do
      expect(described_class.drum(:kick)).to be described_class.drum(:kick)
    end

    it "kickは低域に、hatは高域にエネルギーがある" do
      kick = described_class.drum(:kick)
      hat  = described_class.drum(:hat)

      expect(amplitude_at(kick, 60.0)).to be > amplitude_at(kick, 5000.0) * 10
      expect(amplitude_at(hat, 8000.0)).to be > amplitude_at(hat, 60.0)
    end

    it "snareは185Hzのボディを持つ" do
      expect(amplitude_at(described_class.drum(:snare), 185.0)).to be > 0.05
    end
  end

  describe "決定論（シード固定）" do
    it "ノイズを使うkickでも毎回同じ波形になる" do
      expect(described_class.synth_kick).to eq described_class.synth_kick
    end

    it "snareもhatも毎回同じ波形になる" do
      expect(described_class.synth_snare).to eq described_class.synth_snare
      expect(described_class.synth_hat).to eq described_class.synth_hat
    end

    it "Kernel.srandの状態に影響されない" do
      Kernel.srand 1
      first = described_class.synth_snare
      Kernel.srand 999_999
      expect(described_class.synth_snare).to eq first
    end
  end
end
