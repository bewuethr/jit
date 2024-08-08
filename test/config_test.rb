require "minitest/autorun"

require "fileutils"
require "pathname"

require "config"

class TestConfig < Minitest::Test
  def open_config = Config.new(Pathname.new(@path)).tap(&:open)

  def setup
    @path = File.expand_path("../test-config", __FILE__)
    @config = open_config
  end

  def teardown = FileUtils.rm_rf(@path)
end

class TestConfigInMemory < TestConfig
  def setup = super

  def test_return_nil_for_unknown_key
    assert_nil(@config.get(%w[core editor]))
  end

  def test_return_value_for_known_key
    @config.set(%w[core editor], "ed")
    assert_equal("ed", @config.get(%w[core editor]))
  end

  def test_treat_section_names_case_insensitive
    @config.set(%w[core editor], "ed")
    assert_equal("ed", @config.get(%w[Core editor]))
  end

  def test_treat_variable_names_case_insensitive
    @config.set(%w[core editor], "ed")
    assert_equal("ed", @config.get(%w[core Editor]))
  end

  def test_retrieve_values_from_subsections
    @config.set(%w[branch main remote], "origin")
    assert_equal("origin", @config.get(%w[branch main remote]))
  end

  def test_treat_subsection_names_case_sensitive
    @config.set(%w[branch main remote], "origin")
    assert_nil(@config.get(%w[branch Main remote]))
  end

  def test_add_multiple_values_for_key
    key = %w[remote origin fetch]

    @config.add(key, "main")
    @config.add(key, "topic")

    assert_equal("topic", @config.get(key))
    assert_equal(["main", "topic"], @config.get_all(key))
  end

  def test_refuse_setting_value_for_multi_valued_key
    key = %w[remote origin fetch]

    @config.add(key, "main")
    @config.add(key, "topic")

    assert_raises(Config::Conflict) { @config.set(key, "new-value") }
  end

  def test_replace_all_values_for_multi_valued_key
    key = %w[remote origin fetch]

    @config.add(key, "main")
    @config.add(key, "topic")
    @config.replace_all(key, "new-value")

    assert_equal(["new-value"], @config.get_all(key))
  end
end

class TestConfigFileStorage < TestConfig
  def assert_file(contents) = assert_equal(contents, File.read(@path))

  def setup
    super

    @config.open_for_update
  end

  def test_write_single_setting
    @config.set(%w[core editor], "ed")
    @config.save

    assert_file <<~EOF
      [core]
      \teditor = ed
    EOF
  end

  def test_write_multiple_settings
    @config.set(%w[core editor], "ed")
    @config.set(%w[user name], "A. U. Thor")
    @config.set(%w[Core bare], true)
    @config.save

    assert_file <<~EOF
      [core]
      \teditor = ed
      \tbare = true
      [user]
      \tname = A. U. Thor
    EOF
  end

  def test_write_multiple_subsections
    @config.set(%w[branch main remote], "origin")
    @config.set(%w[branch Main remote], "another")
    @config.save

    assert_file <<~EOF
      [branch "main"]
      \tremote = origin
      [branch "Main"]
      \tremote = another
    EOF
  end

  def test_overwrite_variable_with_matching_name
    @config.set(%w[merge conflictstyle], "diff3")
    @config.set(%w[merge ConflictStyle], "none")
    @config.save

    assert_file <<~EOF
      [merge]
      \tConflictStyle = none
    EOF
  end

  def test_retrieve_persisted_settings
    @config.set(%w[core editor], "ed")
    @config.save

    assert_equal("ed", open_config.get(%w[core editor]))
  end

  def test_retrieve_variables_from_subsections
    @config.set(%w[branch main remote], "origin")
    @config.set(%w[branch Main remote], "another")
    @config.save

    assert_equal("origin", open_config.get(%w[branch main remote]))
    assert_equal("another", open_config.get(%w[branch Main remote]))
  end

  def test_retrieve_variables_from_subsections_including_dots
    @config.set(%w[url git@github.com: insteadOf], "gh:")
    @config.save

    assert_equal("gh:", open_config.get(%w[url git@github.com: insteadOf]))
  end

  def test_retain_formatting_of_existing_settings
    @config.set(%w[core Editor], "ed")
    @config.set(%w[user Name], "A. U. Thor")
    @config.set(%w[core Bare], true)
    @config.save

    config = open_config
    config.open_for_update
    config.set(%w[Core bare], false)
    config.save

    assert_file <<~EOF
      [core]
      \tEditor = ed
      \tbare = false
      [user]
      \tName = A. U. Thor
    EOF
  end
end
