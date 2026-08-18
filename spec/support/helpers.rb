require "open3"

module Muscript
  # specから音を「読む」ための道具。耳の代わりに使う。
  module SpecHelpers
    # ffmpegが無い環境でも他のspecは回したい。audio系だけ落とす判断に使う。
    FFMPEG_AVAILABLE = Muscript::Audio.available?

    # 一時ディレクトリの中でブロックを実行し、パスを組むための小さな糖衣。
    def in_tmpdir
      Dir.mktmpdir("muscript-spec") { |dir| yield dir }
    end

    # Project#render は要約行をstdoutに出す。出力そのものを検証しない時は黙らせる。
    def silent_render(project, path)
      original = $stdout
      $stdout = StringIO.new
      project.render(path)
    ensure
      $stdout = original
    end

    # Wav.write が書いたファイルを読み戻す。ヘッダの検証にも使えるよう生の値で返す。
    def read_wav(path)
      bytes = File.binread(path)
      raise "not a RIFF/WAVE file" unless bytes[0, 4] == "RIFF" && bytes[8, 4] == "WAVE"

      audio_format, channels, sample_rate, byte_rate, block_align, bits =
        bytes[20, 16].unpack("vvVVvv")
      data_size = bytes[40, 4].unpack1("V")
      samples = bytes[44, data_size].unpack("s<*")

      {
        riff_size: bytes[4, 4].unpack1("V"),
        audio_format:, channels:, sample_rate:, byte_rate:, block_align:, bits:,
        data_size:,
        left: samples.each_slice(2).map(&:first),
        right: samples.each_slice(2).map(&:last),
      }
    end

    # 波形のピークを -1.0..1.0 のスケールで返す。
    def peak_of(*channels)
      channels.flatten.map { |s| s.abs / 32_767.0 }.max || 0.0
    end

    # 指定周波数の振幅（1点DFT）。「サイン波に倍音が無い」を測るための耳。
    def amplitude_at(buf, freq, sample_rate: Muscript::SAMPLE_RATE)
      w = 2.0 * Math::PI * freq / sample_rate
      re = 0.0
      im = 0.0
      buf.each_with_index do |v, i|
        re += v * Math.cos(w * i)
        im -= v * Math.sin(w * i)
      end
      2.0 * Math.sqrt((re * re) + (im * im)) / buf.length
    end

    # イベントを直接持つトラック（DSLを通さずレンダラだけを試したい時に使う）。
    def track_with(buffer, name: :test, at: 0)
      Muscript::Track.new(name).tap { |t| t.add(at, buffer) }
    end

    # 左右で別の中身を持つトラック（ステム由来のイベントを模したもの）。
    def stereo_track_with(left, right, name: :test, at: 0)
      Muscript::Track.new(name).tap { |t| t.add_stereo(at, left, right) }
    end

    # デコードに食わせる素材。指定した周波数のサイン波を返す。
    def sine(freq, seconds, amplitude: 0.5, sample_rate: Muscript::SAMPLE_RATE)
      length = (sample_rate * seconds).to_i
      Array.new(length) { |i| amplitude * Math.sin(2 * Math::PI * freq * i / sample_rate) }
    end

    # ffmpegで別形式に変換する。「形式を選ばない」を測るために使う。
    def transcode(src, dest, *ffmpeg_args)
      _, status = Open3.capture2e("ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src, *ffmpeg_args, dest)
      raise "ffmpeg failed to write #{dest}" unless status.success?

      dest
    end

    # 2つの波形のいちばん大きなズレ。16bitの丸め誤差(約3.1e-5)と比べるために使う。
    def max_diff(a, b)
      a.each_with_index.map { |v, i| (v - b[i]).abs }.max
    end
  end
end
