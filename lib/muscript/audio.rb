require "fileutils"
require "open3"

module Muscript
  # 音声ファイルの読み込み。デコード・リサンプル・チャンネル変換はぜんぶffmpegに任せ、
  # Ruby側はバッファを持つだけにする。DSPは発明しない。
  module Audio
    # ffmpegの場所を差し替えたい時のための逃げ道(CIやテスト用)。
    FFMPEG = ENV.fetch("MUSCRIPT_FFMPEG", "ffmpeg")

    # ステレオ1フレーム = f32le × 2ch。
    BYTES_PER_FRAME = 8
    CHUNK_BYTES = 1 << 16 # 64KiB(8192フレーム)ずつ読む。長いステムでも生データを丸ごと抱えない

    class Error < StandardError; end

    # 読み込んだ素材。左右で別のバッファを持つ(-1.0..1.0)。
    Clip = Data.define(:path, :left, :right, :sample_rate) do
      def length = left.length
      def duration = length / sample_rate.to_f
    end

    module_function

    # 形式は問わない(WAV/AIFF/mp3/flac...)。ffmpegが読めるものならそのまま読める。
    # モノラルの素材は左右に複製される(ffmpegの等パワー変換なので音量感は変わらない)。
    def load(path, sample_rate: SAMPLE_RATE)
      file = source_file(path)

      left, right = decode(file, sample_rate)
      raise Error, "no audio decoded from #{path}" if left.empty?

      Clip.new(path: path.to_s, left:, right:, sample_rate:)
    end

    # 素材のパスを絶対パスにして、読む前に存在だけ確かめる。
    def source_file(path)
      file = File.expand_path(path.to_s)
      raise Error, "audio file not found: #{path}" unless File.file?(file)

      file
    end

    # 素材を 44.1kHz / ステレオ / 32bit float のWAVに揃えて書き出す。
    # rubberbandに渡す前の下ごしらえ。16bitに落とさないので、伸ばす前に精度を失わない。
    def export_wav(path, dest, sample_rate: SAMPLE_RATE)
      file = source_file(path)
      FileUtils.mkdir_p(File.dirname(dest))

      out, status = Open3.capture2e(FFMPEG, "-nostdin", "-v", "error", "-y",
                                    "-i", file,
                                    "-map", "0:a:0",
                                    "-c:a", "pcm_f32le",
                                    "-ac", "2",
                                    "-ar", sample_rate.to_s,
                                    dest)
      raise Error, "ffmpeg failed to convert #{path}: #{out.to_s.strip}" unless status.success?

      dest
    rescue Errno::ENOENT
      raise Error, "ffmpeg not found (#{FFMPEG}). Install it with `brew install ffmpeg`"
    end

    # ffmpegが使えるか。無ければステム関連の機能は使えない。
    def available?
      _, status = Open3.capture2e(FFMPEG, "-version")
      status.success?
    rescue Errno::ENOENT
      false
    end

    # ffmpeg -i in.wav -f f32le -ar 44100 - を読みながらデインタリーブする。
    def decode(file, sample_rate)
      left = []
      right = []
      rest = +"".b
      messages = nil
      status = nil

      Open3.popen3(*decode_command(file, sample_rate)) do |stdin, out, err, wait|
        stdin.close
        out.binmode
        drain = Thread.new { err.read } # stderrを読まないままだと詰まる時がある

        while (chunk = out.read(CHUNK_BYTES))
          rest << chunk
          frames = rest.bytesize / BYTES_PER_FRAME
          next if frames.zero?

          deinterleave(rest.unpack("e#{frames * 2}"), left, right)
          rest = rest.byteslice(frames * BYTES_PER_FRAME, rest.bytesize)
        end

        messages = drain.value
        status = wait.value
      end
      raise Error, "ffmpeg failed to decode #{file}: #{messages.to_s.strip}" unless status.success?

      [left, right]
    rescue Errno::ENOENT
      raise Error, "ffmpeg not found (#{FFMPEG}). Install it with `brew install ffmpeg`"
    end

    def decode_command(file, sample_rate)
      [FFMPEG, "-nostdin", "-v", "error",
       "-i", file,
       "-map", "0:a:0", # 音声の1本目だけ。mp3のジャケット画像などは無視する
       "-f", "f32le",
       "-ac", "2",
       "-ar", sample_rate.to_s,
       "-"]
    end

    def deinterleave(samples, left, right)
      i = 0
      while i < samples.length
        left  << samples[i]
        right << samples[i + 1]
        i += 2
      end
    end
  end
end
