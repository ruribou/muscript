module Muscript
  # v0の内蔵音源。モノラルのFloat配列(-1.0..1.0)を返す。
  # ステムが使えるようになるまでの、動作確認用の音でもある。
  module Synth
    NOISE_SEED = 20_260_817 # 決定論の掟: 同じコードからは同じ音
    ATTACK_SAMPLES = 220    # ~5ms クリックノイズ防止
    RELEASE_SAMPLES = 880   # ~20ms

    @drum_cache = {}

    module_function

    def tone(shape, freq, length, sr: SAMPLE_RATE)
      buf = Array.new(length)
      case shape
      when :sine
        w = 2.0 * Math::PI * freq / sr
        length.times { |i| buf[i] = Math.sin(w * i) }
      when :saw
        # 加算合成のsaw。ベース帯域ならエイリアスは実用上問題ない
        harmonics = [12, (sr / 2.0 / freq).floor].min
        w = 2.0 * Math::PI * freq / sr
        length.times do |i|
          v = 0.0
          (1..harmonics).each { |k| v += Math.sin(w * k * i) / k }
          buf[i] = v * 0.6
        end
      else
        raise ArgumentError, "unknown synth shape: #{shape.inspect}"
      end
      envelope!(buf)
    end

    def drum(name)
      @drum_cache[name] ||=
        case name
        when :kick  then synth_kick
        when :snare then synth_snare
        when :hat   then synth_hat
        else raise ArgumentError, "unknown drum: #{name.inspect}"
        end
    end

    def envelope!(buf)
      a = [ATTACK_SAMPLES, buf.length].min
      a.times { |i| buf[i] *= i / a.to_f }
      r = [RELEASE_SAMPLES, buf.length].min
      r.times { |i| buf[-1 - i] *= i / r.to_f }
      buf
    end

    def synth_kick(sr: SAMPLE_RATE)
      n = (sr * 0.16).to_i
      rng = Random.new(NOISE_SEED)
      phase = 0.0
      Array.new(n) do |i|
        t = i / sr.to_f
        f = 45.0 + 75.0 * Math.exp(-t / 0.03) # 120Hz→45Hzのピッチスイープ
        phase += 2.0 * Math::PI * f / sr
        v = Math.sin(phase) * Math.exp(-t / 0.06)
        v += (rng.rand * 2 - 1) * 0.25 * Math.exp(-t / 0.003) # アタックのクリック
        v
      end
    end

    def synth_snare(sr: SAMPLE_RATE)
      n = (sr * 0.18).to_i
      rng = Random.new(NOISE_SEED)
      Array.new(n) do |i|
        t = i / sr.to_f
        noise = (rng.rand * 2 - 1) * Math.exp(-t / 0.05) * 0.7
        body  = Math.sin(2.0 * Math::PI * 185.0 * t) * Math.exp(-t / 0.03) * 0.5
        noise + body
      end
    end

    def synth_hat(sr: SAMPLE_RATE)
      n = (sr * 0.07).to_i
      rng = Random.new(NOISE_SEED)
      prev = 0.0
      Array.new(n) do |i|
        t = i / sr.to_f
        w = rng.rand * 2 - 1
        v = (w - prev) * 0.7 * Math.exp(-t / 0.02) # 1次差分で高域だけ残す
        prev = w
        v
      end
    end
  end
end
