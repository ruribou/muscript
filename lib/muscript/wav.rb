require "fileutils"

module Muscript
  # 16bit PCMステレオWAVの書き出し。依存ゼロの素朴な実装。
  module Wav
    module_function

    def write(path, left, right, sample_rate: SAMPLE_RATE)
      FileUtils.mkdir_p(File.dirname(path))

      interleaved = Array.new(left.length * 2)
      left.each_index do |i|
        interleaved[i * 2]     = (left[i].clamp(-1.0, 1.0) * 32_767).round
        interleaved[i * 2 + 1] = (right[i].clamp(-1.0, 1.0) * 32_767).round
      end
      data = interleaved.pack("s<*")

      File.open(path, "wb") do |f|
        f.write("RIFF")
        f.write([36 + data.bytesize].pack("V"))
        f.write("WAVEfmt ")
        f.write([16, 1, 2, sample_rate, sample_rate * 4, 4, 16].pack("VvvVVvv"))
        f.write("data")
        f.write([data.bytesize].pack("V"))
        f.write(data)
      end
      path
    end
  end
end
