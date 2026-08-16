# muscript

**Music as Code — 実行可能な楽譜と、そのビルドツールチェーン**

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

## これは何?

muscriptは、Ruby DSLで曲の構造を宣言的に記述し、オーディオにビルドするツールです。
ライブコーディング環境ではなく、GUIのDAWでもありません。

楽譜は人類最古の宣言的DSLです。音の高さ・長さ・強弱を宣言し、実行(演奏)は奏者に委ねる。
muscriptはそれを機械が実行できる形にして、Terraformがインフラにもたらしたワークフローを音楽に持ち込みます。

- **宣言的** — 曲は「操作の手順」ではなく「構造」として記述する
- **決定論的** — 同じコード + 同じ素材は、同じWAVになる(乱数はすべてシード付き)
- **Git-native** — 差分レビュー、ブランチでアレンジ違い、CIでレンダリング
- **音楽理論がファーストクラス** — key / scale / degree / コード進行をコードで扱う

| Terraform | muscript |
|---|---|
| HCLで望む状態を宣言 | DSLで曲の構造を宣言 |
| `terraform plan` | `mus plan` — 音を出さずに差分を音楽的語彙で表示 |
| `terraform apply` | `mus render` |
| 冪等性 | 決定論(同じコード = 同じWAV) |
| provider | 出力先: WAV / MIDI / REAPER |
| module | パターン・進行・ミックスチェーンの再利用 |

## 到達目標

> プログラマがコードだけで、既存曲のStemを使ったRemixを1曲完成させられる

ロードマップは [Issues](../../issues) と [Milestones](../../milestones) にあります。

## 思想

1. **聴くまでのループを遅くする機能は追加しない。** DAWのノブの即時性に対するmuscriptの回答は、キャッシュと部分レンダリングと`mus watch`。
2. **DSPは発明しない。** デコードはffmpeg、タイムストレッチはRubber Band。巨人の肩に乗る。
3. **DAWを置き換えない。** アレンジと構造の8割をコードで書き、最後の磨きはREAPERやLogicでどうぞ。エクスポートは一方向。
4. **DSLは薄い糖衣。** 中身はプレーンなRubyオブジェクトと、JSONの中間表現(IR)。魔法は使わない。

## 動かす

```
# 必要なもの: Ruby 3.4+ (現時点で実行時のgem依存はゼロ)
git clone https://github.com/ruribou/muscript.git
cd muscript
ruby examples/hello.rb
afplay out/hello.wav   # macOS
```

ステム加工が入ると ffmpeg と rubberband が必要になります(`brew install ffmpeg rubberband`)。

## Status

実験段階です。作者がこのツールでRemixを1曲完成させるまで、APIは容赦なく変わります。
