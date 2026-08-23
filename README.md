# muscript

Rubyで曲の骨組みを書いて、WAVにするための小さな実験です。

```ruby
require "muscript"

song = Muscript.project "Hello, DnB" do
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

song.render "out/hello.wav"
```

```
$ ruby examples/hello.rb
Hello, DnB | 2 tracks | 5.91s | peak 3.3 dBFS (normalized to -1dBFS) -> out/hello.wav
```

## muscriptについて

muscriptは、Ruby DSLで曲の構造を書き、オーディオとして書き出すためのツールです。リズムやベースライン、コード進行といった「曲の設計図」をコードで持てたら便利そうだ、というところから始めました。

ライブコーディング環境でも、GUIのDAWでもありません。制作中にパラメータを触り続ける代わりに、曲の構造をテキストとして残し、必要なときにレンダリングします。楽譜に近い感覚かもしれません。

目指しているのは、たとえば次のような作り方です。

- 曲を操作の履歴ではなく、構造として書く
- 同じコードと素材からは同じWAVを出す（乱数を使う場合もシードを固定する）
- Gitで差分を見たり、アレンジ違いをブランチで試したりする
- key / scale / degree / コード進行を、値として素直に扱う

Terraformのように、テキストに書いたものを再現できるワークフローを音楽にも持ち込みたい、というイメージです。ただし、インフラの概念をそのまま音楽に当てはめることが目的ではありません。

## まず目指すところ

> プログラマがコードだけで、既存曲のStemを使ったRemixを1曲完成させられる

細かな予定は [Issues](../../issues) と [Milestones](../../milestones) に置いています。

## いまの方針

1. 試して聴くまでの時間は、できるだけ短く保つ。キャッシュ、部分レンダリング、`mus watch`はそのためにあります。
2. 音声処理を一から作り直さない。デコードにはffmpeg、タイムストレッチにはRubber Bandを使います。
3. DAWの代わりにはならない。アレンジや構造はコードで書き、仕上げはREAPERやLogicでやる、という役割分担を想定しています。
4. DSLは薄くする。中身はRubyオブジェクトとJSONの中間表現（IR）で、挙動を追いやすくしておきます。

## 試す

```
# Ruby 4.0 以降が必要です。現時点では実行時のgem依存はありません。
git clone https://github.com/ruribou/muscript.git
cd muscript
ruby examples/hello.rb
afplay out/hello.wav   # macOS
```

ステムを読み込むにはffmpegが、テンポやキーを合わせるにはrubberbandが要ります。

```
brew install ffmpeg rubberband
```

## ステムを読む

`audio` に音声ファイルを渡すと、そのままトラックの素材になります。形式は問いません（WAV/AIFF/mp3/flac...）。
デコードと44.1kHzへのリサンプルはffmpegに任せているので、muscript側は波形を受け取って混ぜるだけです。

```ruby
song = Muscript.project "Stem Remix" do
  bpm 174

  track :vocals do
    audio "stems/vocals.wav"
    gain(-3)
    pan 0.2
  end

  track :drums do
    audio "stems/drums.flac"
  end
end
```

ステレオのまま持つので、素材の左右は潰れません。`pan` の意味は素材によって変わります。

- 内蔵音源（モノ）: 等パワーパン。センターでは左右に -3dB ずつ振り分ける
- ステム（ステレオ）: バランス。センターでは素通しで、振った側の反対チャンネルだけを絞る

手持ちのファイルで試すときは、`stems/` に置いて次を実行します（`stems/` はGit管理外です）。

```
ruby examples/stem.rb
afplay out/stem.wav   # macOS
```

`stems/` が空のときは、muscript自身の音でデモ用のステムを書き出してから、それを読み直します。

## テンポとキーを合わせる

BPMの違うステムをプロジェクトのテンポに揃えます。`audio` に素材のテンポを渡すと、そのぶんだけ伸び縮みします。

```ruby
song = Muscript.project "Remix" do
  bpm 174

  track :break do
    audio "stems/amen.wav", bpm: 140    # 140 -> 174
  end

  track :vocals do
    audio "stems/vocals.wav", bpm: 90   # 90 -> 174
    transpose 2                         # 素材はDキー、曲はEキー
  end
end
```

- `bpm:` は素材側の事実です。書かなければ今までどおり、そのままの速さで鳴ります。BPMの自動検出はしません。
- `warp_to` で揃え先を変えられます（`warp_to 87` なら半分のテンポ）。既定はプロジェクトのBPMです。
- `transpose` は半音単位のピッチシフトで、長さは変わりません。いまはステムだけに効きます。
- テンポは書き残したいけれど伸ばしたくない時は `audio "...", bpm: 140, warp: false` です。

伸縮とピッチシフトは [Rubber Band](https://breakfastquay.com/rubberband/) CLI（R3エンジン）に任せています。`--time` と `--pitch` は一度に渡すので、素材を二度通すことはありません。

出てくるサンプル数は `round(元の長さ × 素材のBPM ÷ 揃え先のBPM)` ちょうどです。同じ小節数の素材なら、もとのテンポが違っても同じ長さに揃います。

```
$ ruby examples/warp.rb
demo-break-140 | 1 tracks | 7.21s | peak 3.0 dBFS (normalized to -1dBFS) -> stems/demo-break-140.wav
demo-bass-90 | 1 tracks | 10.80s | peak -2.7 dBFS -> stems/demo-bass-90.wav
Warp Test | 2 tracks | 6.02s | peak -2.0 dBFS -> out/warp.wav
```

### 中間ファイルのキャッシュ

伸ばした結果は `.muscript/cache/` に置いて、次からは使い回します。キーは素材の中身のハッシュ・比率・半音・rubberbandの版なので、どれかが変われば計算し直します。上の例だと、1回目は0.96秒、2回目は0.23秒です。

トラック単位のキャッシュや世代管理はこれからで、ここはその最初の一段です。

## 開発

テストはRSpecです。開発用のgemだけBundlerで入れます。

```
bundle install
bundle exec rspec
```

`spec/muscript/` は音名・波形・WAV・ミックスといった部品ごとのテスト、`spec/integration/` は
`examples/` を実際にレンダリングする受け入れテストです。「同じコードからは同じWAVが出る」
という決定論も、ここで確かめています。ffmpegやrubberbandが入っていない環境では、それを使う
テストは落とさずにスキップします。

## 状態

まだ実験段階です。作者自身がこれでRemixを1曲完成させるまでは、APIを大きく変えることがあります。
