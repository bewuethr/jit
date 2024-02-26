require "minitest/autorun"

require_relative "../command_helper"

class Command::TestMerge < Minitest::Test
  include CommandHelper

  def commit_tree(message, files)
    files.each do |path, contents|
      write_file(path, contents)
    end

    jit_cmd("add", ".")
    commit(message)
  end
end

class Command::TestMergeUnconflictedTwoFiles < Command::TestMerge
  #   A   B   M
  #   o---o---o
  #    \     /
  #     `---o
  #         C

  def setup
    super

    commit_tree("root", {
      "f.txt" => "1",
      "g.txt" => "1"
    })

    jit_cmd("branch", "topic")
    jit_cmd("checkout", "topic")
    commit_tree("right", {"g.txt" => "2"})

    jit_cmd("checkout", "main")
    commit_tree("left", {"f.txt" => "2"})

    set_stdin("merg topic branch")
    jit_cmd("merge", "topic")
  end

  def test_put_combined_changes_in_workspace
    assert_workspace({
      "f.txt" => "2",
      "g.txt" => "2"
    })
  end

  def test_leave_status_clean
    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end

  def test_write_commit_with_old_head_and_merged_commit_as_parents
    commit = load_commit("@")
    old_head = load_commit("@^")
    merge_head = load_commit("topic")

    assert_equal([old_head.oid, merge_head.oid], commit.parents)
  end
end
