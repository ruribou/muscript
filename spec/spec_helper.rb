require "stringio"
require "tmpdir"

require_relative "../lib/muscript"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.disable_monkey_patching!
  config.order = :random
  config.example_status_persistence_file_path = ".rspec_status"
  config.filter_run_when_matching :focus

  config.include Muscript::SpecHelpers

  # :ffmpeg を付けたspecは、ffmpegが無ければ落とさずスキップする。
  config.before(:each, :ffmpeg) do
    skip "ffmpeg が無い環境なのでスキップ" unless Muscript::SpecHelpers::FFMPEG_AVAILABLE
  end
end
