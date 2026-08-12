# frozen_string_literal: true

require "yaml"

class ActionPinChecker
  SHA_PATTERN = /\A[0-9a-f]{40}\z/
  DIGEST_PATTERN = /\A[0-9a-f]{64}\z/

  attr_reader :errors

  def initialize(paths)
    @paths = paths
    @errors = []
  end

  def check
    @paths.each { |path| check_file(path) }
    self
  end

  private

  def check_file(path)
    document = YAML.safe_load_file(path, aliases: true)
    visit(document, path)
  rescue Psych::Exception => error
    @errors << "#{path}: invalid YAML: #{error.message}"
  end

  def visit(value, path)
    case value
    when Hash
      value.each do |key, child|
        check_action(child, path) if key.to_s == "uses"
        visit(child, path)
      end
    when Array
      value.each { |child| visit(child, path) }
    end
  end

  def check_action(action, path)
    unless action.is_a?(String)
      @errors << "#{path}: action declaration must be a string: #{action.inspect}"
      return
    end

    return if action.start_with?("./")

    if action.start_with?("docker://")
      digest = action.split("@sha256:", 2)[1]
      unless digest&.match?(DIGEST_PATTERN)
        @errors << "#{path}: container action is not pinned to a full SHA-256 digest: #{action}"
      end
      return
    end

    reference = action.rpartition("@").last
    unless reference.match?(SHA_PATTERN)
      @errors << "#{path}: GitHub Action is not pinned to a full commit SHA: #{action}"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  paths = ARGV.flat_map do |argument|
    File.directory?(argument) ? Dir[File.join(argument, "**", "*.{yml,yaml}")] : argument
  end

  checker = ActionPinChecker.new(paths).check
  unless checker.errors.empty?
    warn checker.errors.join("\n")
    exit 1
  end
end
