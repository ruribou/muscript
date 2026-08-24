RSpec.describe Muscript::Arrangement do
  subject(:arrangement) { described_class.new }

  it "セクションが無いところから始まる" do
    expect(arrangement).to be_empty
    expect(arrangement.count).to eq 0
    expect(arrangement.finish).to eq 0.0
  end

  describe "#add" do
    it "書いた順に前のセクションの後ろへ並べる" do
      arrangement.add(:intro, bars: 8)
      arrangement.add(:drop, bars: 16)

      expect(arrangement.sections.map(&:name)).to eq %i[intro drop]
      expect(arrangement.sections.map(&:start)).to eq [0.0, 32.0]
      expect(arrangement.finish).to eq 96.0 # 24小節
    end

    it "長さを拍で持つ（小節でも拍でも書ける）" do
      expect(arrangement.add(:intro, bars: 2).length).to eq 8.0
      expect(arrangement.add(:hit, beats: 2).length).to eq 2.0
      expect(arrangement.fetch(:hit).start).to eq 8.0
    end

    it "作ったセクションを返す" do
      section = arrangement.add(:drop, bars: 16)

      expect(section.name).to eq :drop
      expect(section.bars).to eq 16.0
      expect(section.finish).to eq 64.0
    end

    it "長さを言われなければ、何を書けばいいか教えて落ちる" do
      expect { arrangement.add(:intro) }.to raise_error(ArgumentError, /give bars: or beats:/)
    end

    it "0小節のセクションを拒否する" do
      expect { arrangement.add(:intro, bars: 0) }.to raise_error(ArgumentError, /must be positive/)
    end

    it "同じ名前を二度定義したら落ちる" do
      arrangement.add(:intro, bars: 8)

      expect { arrangement.add(:intro, bars: 4) }
        .to raise_error(ArgumentError, "section :intro is already defined")
    end
  end

  describe "#fetch" do
    it "名前で引ける" do
      arrangement.add(:intro, bars: 8)

      expect(arrangement.fetch(:intro).start).to eq 0.0
    end

    it "知らない名前なら、知っているセクションを添えて落ちる" do
      arrangement.add(:intro, bars: 8)
      arrangement.add(:drop, bars: 16)

      expect { arrangement.fetch(:build) }
        .to raise_error(ArgumentError, "unknown section :build (known sections: :intro, :drop)")
    end

    it "まだ何も無いなら、どこに書けばいいかを教える" do
      expect { arrangement.fetch(:drop) }
        .to raise_error(ArgumentError, /sections are declared before the tracks: section :intro, bars: 8/)
    end
  end
end
