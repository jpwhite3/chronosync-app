# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "yaml"

class CheckCodeqlConfigTest < Minitest::Test
  REPOSITORY_ROOT = Pathname(__dir__).join("../..").expand_path
  CONFIG_PATH = REPOSITORY_ROOT.join(".github/codeql/codeql-config.yml")
  SECURITY_WORKFLOW_PATH = REPOSITORY_ROOT.join(".github/workflows/security.yml")

  def test_codeql_config_exists
    assert_predicate CONFIG_PATH, :file?
  end

  def test_config_scans_first_party_sources_and_ignores_generated_worker
    config = YAML.safe_load_file(CONFIG_PATH, aliases: false)

    assert_includes config.fetch("paths"), "relay/src"
    assert_includes config.fetch("paths"), "chronosync/assets/nearby_client"
    assert_includes config.fetch("paths"), "chronosync/web"
    assert_includes config.fetch("paths-ignore"),
                    "chronosync/web/drift_worker.js"
  end

  def test_security_workflow_loads_the_config
    workflow = SECURITY_WORKFLOW_PATH.read

    assert_includes workflow,
                    "config-file: ./.github/codeql/codeql-config.yml"
  end
end
