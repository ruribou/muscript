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

ステムを加工する機能を使う場合は、ffmpeg と rubberband も入れてください。

```
brew install ffmpeg rubberband
```

## 開発

テストはRSpecです。開発用のgemだけBundlerで入れます。

```
bundle install
bundle exec rspec
```

`spec/muscript/` は音名・波形・WAV・ミックスといった部品ごとのテスト、`spec/integration/` は
`examples/` を実際にレンダリングする受け入れテストです。「同じコードからは同じWAVが出る」
という決定論も、ここで確かめています。

## 状態

まだ実験段階です。作者自身がこれでRemixを1曲完成させるまでは、APIを大きく変えることがあります。
