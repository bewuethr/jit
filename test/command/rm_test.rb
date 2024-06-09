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
end
