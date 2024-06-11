require "minitest/autorun"

require_relative "../command_helper"

class Command::TestRm < Minitest::Test
  include CommandHelper

  def setup
    super

    write_file("f.txt", "1")

    jit_cmd("add", ".")
    commit("first")
  end
end

class Command::TestRmWithSingleFile < Command::TestRm
  def test_exit_successfully
    jit_cmd("rm", "f.txt")
    assert_status(0)
  end

  def test_remove_file_from_index
    jit_cmd("rm", "f.txt")

    repo.index.load
    refute(repo.index.tracked_file?("f.txt"))
  end

  def test_remove_file_from_workspace
    jit_cmd("rm", "f.txt")

    assert_workspace({})
  end

  def test_succeed_if_file_not_in_workspace
    delete("f.txt")
    jit_cmd("rm", "f.txt")

    assert_status(0)

    repo.index.load
    refute(repo.index.tracked_file?("f.txt"))
  end

  def test_fail_if_file_not_in_index
    jit_cmd("rm", "nope.txt")
    assert_status(128)
    assert_stderr("fatal: pathspec 'nope.txt' did not match any files\n")
  end

  def test_fail_if_file_has_unstaged_changes
    sleep 0.01
    write_file("f.txt", "2")
    jit_cmd("rm", "f.txt")

    assert_stderr <<~EOF
      error: the following file has local modifications:
          f.txt
    EOF

    assert_status(1)

    repo.index.load
    assert(repo.index.tracked_file?("f.txt"))
    assert_workspace("f.txt" => "2")
  end

  def test_fail_if_file_has_uncommitted_changes
    sleep 0.001
    write_file("f.txt", "2")
    jit_cmd("add", "f.txt")
    jit_cmd("rm", "f.txt")

    assert_stderr <<~EOF
      error: the following file has changes staged in the index:
          f.txt
    EOF

    assert_status(1)

    repo.index.load
    assert(repo.index.tracked_file?("f.txt"))
    assert_workspace("f.txt" => "2")
  end
end
