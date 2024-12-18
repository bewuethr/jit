require "minitest/autorun"

require_relative "../command_helper"

class Command::TestRm < Minitest::Test
  include CommandHelper
end

class Command::TestRmWithSingleFile < Command::TestRm
  def setup
    super

    write_file("f.txt", "1")

    jit_cmd("add", ".")
    commit("first")
  end

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

  def test_force_removal_of_unstaged_changes
    write_file("f.txt", "2")
    jit_cmd("rm", "-f", "f.txt")

    repo.index.load
    refute(repo.index.tracked_file?("f.txt"))
    assert_workspace({})
  end

  def test_force_removal_of_uncommitted_changes
    write_file("f.txt", "2")
    jit_cmd("add", "f.txt")
    jit_cmd("rm", "-f", "f.txt")

    repo.index.load
    refute(repo.index.tracked_file?("f.txt"))
    assert_workspace({})
  end

  def test_remove_file_only_from_index
    jit_cmd("rm", "--cached", "f.txt")

    repo.index.load
    refute(repo.index.tracked_file?("f.txt"))
    assert_workspace("f.txt" => "1")
  end

  def test_remove_from_index_if_has_unstaged_changes
    write_file("f.txt", "2")
    jit_cmd("rm", "--cached", "f.txt")

    repo.index.load
    refute(repo.index.tracked_file?("f.txt"))
    assert_workspace("f.txt" => "2")
  end

  def test_remove_from_index_if_has_uncommitted_changes
    write_file("f.txt", "2")
    jit_cmd("add", "f.txt")
    jit_cmd("rm", "--cached", "f.txt")

    repo.index.load
    refute(repo.index.tracked_file?("f.txt"))
    assert_workspace("f.txt" => "2")
  end

  def test_do_not_remove_file_with_uncommitted_and_unstaged_changes
    write_file("f.txt", "2")
    jit_cmd("add", "f.txt")
    sleep 0.01
    write_file("f.txt", "3")
    jit_cmd("rm", "--cached", "f.txt")

    assert_stderr <<~EOF
      error: the following file has staged content different from both the file and the HEAD:
          f.txt
    EOF

    assert_status(1)

    repo.index.load
    assert(repo.index.tracked_file?("f.txt"))
    assert_workspace("f.txt" => "3")
  end
end

class Command::TestRmWithTree < Command::TestRm
  def setup
    super

    write_file("f.txt", "1")
    write_file("outer/g.txt", "2")
    write_file("outer/inner/h.txt", "3")

    jit_cmd("add", ".")
    commit("first")
  end

  def test_remove_multiple_files
    jit_cmd("rm", "f.txt", "outer/inner/h.txt")

    repo.index.load
    assert_equal(["outer/g.txt"], repo.index.each_entry.map(&:path))
    assert_workspace("outer/g.txt" => "2")
  end

  def test_refuse_to_remove_directory
    jit_cmd("rm", "f.txt", "outer")

    assert_stderr("fatal: not removing 'outer' recursively without -r\n")
    assert_status(128)

    repo.index.load
    assert_equal(["f.txt", "outer/g.txt", "outer/inner/h.txt"],
      repo.index.each_entry.map(&:path))
    assert_workspace({
      "f.txt" => "1",
      "outer/g.txt" => "2",
      "outer/inner/h.txt" => "3"
    })
  end

  def test_remove_directory_with_recursive_flag
    jit_cmd("rm", "-r", "outer")

    repo.index.load
    assert_equal(["f.txt"], repo.index.each_entry.map(&:path))
    assert_workspace("f.txt" => "1")
  end

  def test_do_not_remove_untracked_files
    write_file("outer/inner/j.txt", "4")
    jit_cmd("rm", "-r", "outer")

    repo.index.load
    assert_equal(["f.txt"], repo.index.each_entry.map(&:path))
    assert_workspace({
      "f.txt" => "1",
      "outer/inner/j.txt" => "4"
    })
  end
end
