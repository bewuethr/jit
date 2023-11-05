require "minitest/autorun"

require_relative "../command_helper"

class Command::TestBranch < Minitest::Test
  include CommandHelper

  def setup
    super

    write_file("1.txt", "one")
    jit_cmd("add", ".")
    commit("first commit")
  end

  def test_create_new_branch
    jit_cmd("branch", "feature")

    assert_same_content(".git", "HEAD", "refs/heads/feature")
    assert_status(0)
  end

  def test_prevent_duplicate_branch_creation
    jit_cmd("branch", "feature")
    jit_cmd("branch", "feature")

    assert_status(128)
    assert_stderr("fatal: A branch named 'feature' already exists.\n")
  end

  def test_prevent_invalid_branch_names
    [
      ".dot",
      "slash/.dot",
      "dot..dot",
      "/slashstart",
      "slashend/",
      "name.lock",
      "feature@{something}",
      "a space",
      "ast*erisk",
      "col:on",
      "quest?ionmark",
      "brac[ket"
    ].each do |name|
      jit_cmd("branch", name)

      assert_status(128)
      assert_stderr("fatal: '#{name}' is not a valid branch name.\n")
    end
  end
end
