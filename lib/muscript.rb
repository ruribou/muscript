module Muscript
  SAMPLE_RATE = 44_100
end

require_relative "muscript/note"
require_relative "muscript/wav"
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
