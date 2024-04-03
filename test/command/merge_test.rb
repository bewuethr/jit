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

class Command::TestMergeAncestor < Command::TestMerge
  def setup
    super

    commit_tree("A", "f.txt" => "1")
    commit_tree("B", "f.txt" => "2")
    commit_tree("C", "f.txt" => "3")

    jit_cmd("merge", "@^")
  end

  def test_print_up_to_date_message
    assert_stdout("Already up to date.\n")
  end

  def test_does_not_change_repo_state
    commit = load_commit("@")
    assert_equal("C", commit.message)

    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end
end

class Command::TestFastForwardMerge < Command::TestMerge
  def setup
    super

    commit_tree("A", "f.txt" => "1")
    commit_tree("B", "f.txt" => "2")
    commit_tree("C", "f.txt" => "3")

    jit_cmd("branch", "topic", "@^^")
    jit_cmd("checkout", "topic")

    set_stdin("M")
    jit_cmd("merge", "main")
  end

  def test_print_fast_forward_message
    a, b = ["main^^", "main"].map { |rev| resolve_revision(rev) }
    assert_stdout <<~EOF
      Updating #{repo.database.short_oid(a)}..#{repo.database.short_oid(b)}
      Fast-forward
    EOF
  end

  def test_update_current_branch_head
    commit = load_commit("@")
    assert_equal("C", commit.message)

    jit_cmd("status", "--porcelain")
    assert_stdout("")
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
