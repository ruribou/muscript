RSpec.describe Muscript::Note do
  describe ".midi" do
    it "A4を69に、C4を60にする（MIDIの基準点）" do
      expect(described_class.midi("A4")).to eq 69
      expect(described_class.midi("C4")).to eq 60
    end

    it "C-1を0にする（MIDIの最下端）" do
      expect(described_class.midi("C-1")).to eq 0
    end

    it "オクターブが1つ上がると12半音上がる" do
      expect(described_class.midi("E2") - described_class.midi("E1")).to eq 12
    end

    it "#で半音上げ、bで半音下げる" do
      expect(described_class.midi("F#3")).to eq described_class.midi("F3") + 1
      expect(described_class.midi("Gb3")).to eq described_class.midi("G3") - 1
    end

    it "異名同音（F#3とGb3）を同じ番号にする" do
      expect(described_class.midi("F#3")).to eq described_class.midi("Gb3")
    end

    it "Symbolでも受け取る" do
      expect(described_class.midi(:E1)).to eq described_class.midi("E1")
    end

    it "音名として読めない文字列を拒否する" do
      ["H4", "E", "e4", "E2x", "", "_"].each do |bad|
        expect { described_class.midi(bad) }
          .to raise_error(ArgumentError, /invalid note name/), "#{bad.inspect} が通ってしまった"
      end
    end
  end

  describe ".freq" do
    it "A4を440Hzにする" do
      expect(described_class.freq("A4")).to eq 440.0
    end

    it "1オクターブ上げると周波数が2倍になる" do
      expect(described_class.freq("A5")).to be_within(1e-9).of(880.0)
      expect(described_class.freq("A3")).to be_within(1e-9).of(220.0)
    end

    it "ベースの音域を実際の周波数にする（E1 = 41.20Hz）" do
      expect(described_class.freq("E1")).to be_within(0.01).of(41.20)
    end
  end
end
