# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "check_action_pins"

class CheckActionPinsTest < Minitest::Test
  SHA = "a" * 40

  def with_workflow(contents)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "workflow.yml")
      File.write(path, contents)
      yield path
    end
  end

  def test_accepts_full_sha_local_and_container_actions
    with_workflow(<<~YAML) do |path|
      jobs:
        test:
          steps:
            - uses: actions/checkout@#{SHA}
            - uses: ./local-action
            - uses: docker://alpine@sha256:#{"b" * 64}
    YAML
      assert_empty ActionPinChecker.new([path]).check.errors
    end
  end

  def test_rejects_mutable_tag_with_alternate_key_spacing
    with_workflow("jobs:\n  test:\n    steps:\n      - uses : actions/checkout@v4\n") do |path|
      assert_match(/not pinned/, ActionPinChecker.new([path]).check.errors.join("\n"))
    end
  end

  def test_rejects_mutable_tag_in_flow_mapping
    with_workflow("jobs: {test: {steps: [{uses: actions/checkout@v4}]}}\n") do |path|
      assert_match(/not pinned/, ActionPinChecker.new([path]).check.errors.join("\n"))
    end
  end

  def test_rejects_a_non_string_action_declaration
    with_workflow("jobs: {test: {steps: [{uses: 42}]}}\n") do |path|
      assert_match(/must be a string/, ActionPinChecker.new([path]).check.errors.join("\n"))
    end
  end
end
