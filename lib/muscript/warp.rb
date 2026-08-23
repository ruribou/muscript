require "digest"
require "fileutils"
require "open3"
require "tmpdir"

module Muscript
  # タイムストレッチとピッチシフト。rubberband CLI(R3エンジン)にシェルアウトする。
  # 「DSPは発明しない」の続きで、muscriptの仕事は比率を決めることと、結果を憶えておくことだけ。
  module Warp
    # rubberbandの場所を差し替えたい時のための逃げ道(CIやテスト用)。
    RUBBERBAND = ENV.fetch("MUSCRIPT_RUBBERBAND", "rubberband")

    # 伸ばした結果の中間WAVの置き場所。同じ素材・同じ比率なら二度と計算しない。
    # 本格的なキャッシュ(トラック単位・世代管理)は #7 で、ここはその最初の一段。
    CACHE_DIR = ENV.fetch("MUSCRIPT_CACHE_DIR", ".muscript/cache")

    # R2のストレッチはブレイクビーツに耐えないので -3(R3)を使う。R3は3.0から。
    MIN_VERSION = 3

    # キャッシュキーの作り方を変えた時に上げる。古い中間WAVを黙って使い回さないため。
    KEY_VERSION = 1

    # 比率を文字列にする時の桁。コマンドラインとキャッシュキーで同じ表記を使う。
    RATIO_FORMAT = "%.12g"

    class Error < StandardError; end

    module_function

    # 素材を time_ratio 倍の長さに伸縮し、semitones だけピッチを動かしたWAVのパスを返す。
    # time_ratio は「出力の長さ ÷ 入力の長さ」。140BPMの素材を174BPMに合わせるなら 140/174。
    # どちらも動かさない時は rubberband を呼ばず、素材のパスをそのまま返す。
    def process(path, time_ratio: 1.0, semitones: 0.0, sample_rate: SAMPLE_RATE)
      file = Audio.source_file(path)
      return path if identity?(time_ratio, semitones)
      unless time_ratio.to_f.positive? && time_ratio.to_f.finite?
        raise Error, "invalid time ratio: #{time_ratio.inspect}"
      end

      engine = engine_version # 呼ぶ前に確かめる。エンジンの版はキャッシュキーにも混ぜる
      cached = cache_path(file, time_ratio, semitones, sample_rate, engine)
      return cached if File.file?(cached)

      FileUtils.mkdir_p(File.dirname(cached))
      partial = "#{cached}.#{Process.pid}.part"
      Dir.mktmpdir("muscript-warp") do |tmp|
        # rubberbandが読めるのはWAV/AIFFなので、素材はいったんffmpegで揃えてから渡す。
        source = Audio.export_wav(file, File.join(tmp, "source.wav"), sample_rate:)
        run(source, partial, time_ratio, semitones)
      end
      File.rename(partial, cached) # 途中で落ちた半端なWAVをキャッシュに残さない
      cached
    ensure
      File.delete(partial) if partial && File.exist?(partial)
    end

    # ストレッチ比率。from BPMの素材を to BPM に合わせる時に掛ける長さの倍率。
    def ratio(from:, to:)
      raise Error, "invalid bpm: #{from.inspect} -> #{to.inspect}" unless from.to_f.positive? && to.to_f.positive?

      from.to_f / to
    end

    # rubberband CLI が使えるか。R3の無い古い版は「無い」と同じ扱いにする。
    def available?
      version.to_s[/\A\d+/].to_i >= MIN_VERSION
    end

    def version
      out, status = Open3.capture2e(RUBBERBAND, "--version")
      status.success? ? out[/\d+(?:\.\d+)*/] : nil
    rescue Errno::ENOENT
      nil
    end

    def identity?(time_ratio, semitones)
      time_ratio.to_f == 1.0 && semitones.to_f.zero?
    end

    # 使えるrubberbandの版。無い時と古い時は、入れ方を添えてここで落とす。
    def engine_version
      installed = version
      raise Error, install_hint if installed.nil?
      if installed[/\A\d+/].to_i < MIN_VERSION
        raise Error, "rubberband #{installed} is too old (need >= #{MIN_VERSION}.0 for the R3 engine)"
      end

      installed
    end

    def run(source, dest, time_ratio, semitones)
      cmd = [RUBBERBAND, "-3", "-q", "--time", format(RATIO_FORMAT, time_ratio)]
      cmd += ["--pitch", format(RATIO_FORMAT, semitones)] unless semitones.to_f.zero?
      out, status = Open3.capture2e(*cmd, source, dest)
      raise Error, "rubberband failed: #{out.to_s.strip}" unless status.success?

      dest
    rescue Errno::ENOENT
      raise Error, install_hint
    end

    # 内容アドレス。素材の中身が1バイトでも違えば別のキャッシュになる。
    # rubberbandの版も混ぜる(エンジンが変われば出てくる音も変わるため)。
    def cache_path(file, time_ratio, semitones, sample_rate, engine)
      key = Digest::SHA256.hexdigest([
        "muscript-warp/#{KEY_VERSION}",
        Digest::SHA256.file(file).hexdigest,
        format(RATIO_FORMAT, time_ratio),
        format(RATIO_FORMAT, semitones),
        sample_rate,
        "rubberband/#{engine}",
      ].join("\n"))

      File.join(CACHE_DIR, "warp", "#{key}.wav")
    end

    def install_hint
      "rubberband not found (#{RUBBERBAND}). Install it with `brew install rubberband`"
    end
  end
end
