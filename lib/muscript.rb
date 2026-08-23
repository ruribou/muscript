if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("4.0")
  raise "muscript requires Ruby >= 4.0 (running #{RUBY_VERSION})"
end

module Muscript
  SAMPLE_RATE = 44_100
end

require_relative "muscript/note"
require_relative "muscript/wav"
require_relative "muscript/audio"
require_relative "muscript/warp"
require_relative "muscript/stem"
require_relative "muscript/synth"
require_relative "muscript/track"
require_relative "muscript/project"
require_relative "muscript/dsl"

module Muscript
  def self.project(name, &block)
    project = Project.new(name)
    DSL::ProjectDSL.new(project).instance_eval(&block)
    project
  end
end
