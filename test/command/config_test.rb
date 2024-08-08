require "minitest/autorun"

require_relative "../command_helper"

require "rev_list"

class Command::TestRevert < Minitest::Test
  include CommandHelper

  def test_return_1_for_unknown_variable
    jit_cmd("config", "--local", "no.such")
    assert_status(1)
  end

  def test_return_1_when_key_is_invalid
    jit_cmd("config", "--local", "0.0")
    assert_status(1)
    assert_stderr("error: invalid key: 0.0\n")
  end

  def test_return_2_when_no_section_is_given
    jit_cmd("config", "--local", "no")
    assert_status(2)
    assert_stderr("error: key does not contain a section: no\n")
  end

  def test_return_value_of_set_variable
    jit_cmd("config", "core.editor", "ed")

    jit_cmd("config", "--local", "Core.Editor")
    assert_status(0)
    assert_stdout("ed\n")
  end

  def test_return_value_of_set_variable_in_subsection
    jit_cmd("config", "remote.origin.url", "git@github.com:bewuethr.jit")

    jit_cmd("config", "--local", "Remote.origin.URL")
    assert_status(0)
    assert_stdout("git@github.com:bewuethr.jit\n")
  end

  def test_return_last_value_of_multi_valued_variable
    jit_cmd("config", "--add", "remote.origin.fetch", "main")
    jit_cmd("config", "--add", "remote.origin.fetch", "topic")

    jit_cmd("config", "remote.origin.fetch")
    assert_status(0)
    assert_stdout("topic\n")
  end

  def test_return_all_values_of_multi_valued_variable
    jit_cmd("config", "--add", "remote.origin.fetch", "main")
    jit_cmd("config", "--add", "remote.origin.fetch", "topic")

    jit_cmd("config", "--get-all", "remote.origin.fetch")
    assert_status(0)

    assert_stdout <<~EOF
      main
      topic
    EOF
  end

  def test_return_5_when_trying_to_set_multi_valued_variable
    jit_cmd("config", "--add", "remote.origin.fetch", "main")
    jit_cmd("config", "--add", "remote.origin.fetch", "topic")

    jit_cmd("config", "remote.origin.fetch", "new-value")
    assert_status(5)

    jit_cmd("config", "--get-all", "remote.origin.fetch")

    assert_stdout <<~EOF
      main
      topic
    EOF
  end

  def test_replace_multi_valued_variable
    jit_cmd("config", "--add", "remote.origin.fetch", "main")
    jit_cmd("config", "--add", "remote.origin.fetch", "topic")
    jit_cmd("config", "--replace-all", "remote.origin.fetch", "new-value")

    jit_cmd("config", "--get-all", "remote.origin.fetch")
    assert_status(0)
    assert_stdout("new-value\n")
  end
end
