RSpec.describe Muscript::Track do
  subject(:track) { described_class.new(:drums) }

  it "gain 0dB / pan センター / sine で始まる" do
    expect(track.name).to eq :drums
    expect(track.gain_db).to eq 0.0
    expect(track.pan).to eq 0.0
    expect(track.synth_shape).to eq :sine
    expect(track.events).to be_empty
  end

  describe "#add" do
    it "開始サンプル位置とバッファの組で持つ" do
      buf = [0.1, 0.2]
      track.add(100, buf)
      expect(track.events).to eq [{ at: 100, buf: buf }]
    end
  end

  describe "#end_sample" do
    it "イベントが無ければ0" do
      expect(track.end_sample).to eq 0
    end

    it "いちばん後ろで鳴り終わるイベントの終端を返す" do
      track.add(0, Array.new(1000, 0.0))
      track.add(500, Array.new(100, 0.0))   # 先に終わる
      track.add(2000, Array.new(50, 0.0))   # これが終端
      expect(track.end_sample).to eq 2050
    end
  end

  describe "#gain_linear" do
    it "0dBを1.0にする" do
      expect(track.gain_linear).to eq 1.0
    end

    it "-6dBでおよそ半分の振幅にする" do
      track.gain_db = -6.0
      expect(track.gain_linear).to be_within(0.005).of(0.5)
    end

    it "+6dBでおよそ2倍の振幅にする" do
      track.gain_db = 6.0
      expect(track.gain_linear).to be_within(0.01).of(2.0)
    end

    it "-20dBごとに1/10になる" do
      track.gain_db = -20.0
      expect(track.gain_linear).to be_within(1e-9).of(0.1)
    end
  end

  describe "#pan_gains" do
    it "センターでは左右が等しい" do
      l, r = track.pan_gains
      expect(l).to be_within(1e-9).of(r)
    end

    it "どこにパンしても等パワー（L^2 + R^2 = 1）を保つ" do
      [-1.0, -0.5, 0.0, 0.3, 1.0].each do |pan|
        track.pan = pan
        l, r = track.pan_gains
        expect((l * l) + (r * r)).to be_within(1e-9).of(1.0), "pan #{pan} でパワーが崩れた"
      end
    end

    it "左端では右チャンネルが無音になる" do
      track.pan = -1.0
      l, r = track.pan_gains
      expect(l).to be_within(1e-9).of(1.0)
      expect(r).to be_within(1e-9).of(0.0)
    end

    it "右端では左チャンネルが無音になる" do
      track.pan = 1.0
      l, r = track.pan_gains
      expect(l).to be_within(1e-9).of(0.0)
      expect(r).to be_within(1e-9).of(1.0)
    end

    it "panを右に振るほど右が大きく、左が小さくなる" do
      gains = [-1.0, -0.5, 0.0, 0.5, 1.0].map { |p| track.pan = p; track.pan_gains }
      expect(gains.map(&:first)).to eq gains.map(&:first).sort.reverse
      expect(gains.map(&:last)).to eq gains.map(&:last).sort
    end
  end
end
