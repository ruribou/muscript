module Muscript
  # 音名("E2", "F#3", "Bb1")→ 周波数/MIDIノート番号の変換。
  module Note
    SEMITONES = { "C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11 }.freeze

    module_function

    def midi(name)
      m = name.to_s.match(/\A([A-G])([#b]?)(-?\d+)\z/)
      raise ArgumentError, "invalid note name: #{name.inspect}" unless m

      semis = SEMITONES.fetch(m[1])
      semis += 1 if m[2] == "#"
      semis -= 1 if m[2] == "b"
      (m[3].to_i + 1) * 12 + semis
    end

    def freq(name)
      440.0 * (2.0**((midi(name) - 69) / 12.0))
    end
  end
end
