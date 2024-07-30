require "minitest/autorun"

require_relative "../command_helper"

require "rev_list"

class Command::TestRevert < Minitest::Test
  include CommandHelper

  def commit_tree(message, files)
    @time ||= Time.now
    @time += 10

    files.each do |path, contents|
      write_file(path, contents)
    end
    jit_cmd("add", ".")
    commit(message, @time)
  end

  def setup
    super

    ["one", "two", "three", "four"].each do |message|
      commit_tree(message, {"f.txt" => message})
    end

    commit_tree("five", {"g.txt" => "five"})
    commit_tree("six", {"f.txt" => "six"})
    commit_tree("seven", {"g.txt" => "seven"})
    commit_tree("eight", {"g.txt" => "eight"})
  end
end

class Command::TestRevertWithChainOfCommits < Command::TestRevert
  def setup = super

  def test_revert_commit_on_top_of_current_head
    jit_cmd("revert", "@~2")
    assert_status(0)

    revs = RevList.new(repo, ["@~3.."])

    assert_equal(['Revert "six"', "eight", "seven"],
      revs.map{ _1.title_line.strip })

    assert_index({
      "f.txt" => "four",
      "g.txt" => "eight"
    })

    assert_workspace({
      "f.txt" => "four",
      "g.txt" => "eight"
    })
  end

  def test_fail_to_revert_content_conflict
    jit_cmd("revert", "@~4")
    assert_status(1)

    short = repo.database.short_oid(resolve_revision("@~4"))

    assert_workspace({
      "g.txt" => "eight",
      "f.txt" => <<~EOF
        <<<<<<< HEAD
        six=======
        three>>>>>>> parent of #{short}... four
      EOF
    })

    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UU f.txt
    EOF
  end

  def test_fail_to_revert_modify_delete_conflict
    jit_cmd("revert", "@~3")
    assert_status(1)

    assert_workspace({
      "f.txt" => "six",
      "g.txt" => "eight"
    })

    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UD g.txt
    EOF
  end

  def test_continue_conflicted_revert
    jit_cmd("revert", "@~3")
    jit_cmd("add", "g.txt")

    jit_cmd("revert", "--continue")
    assert_status(0)

    commits = RevList.new(repo, ["@~3.."]).to_a
    assert_equal([commits[1].oid], commits[0].parents)

    assert_equal(['Revert "five"', "eight", "seven"],
      commits.map{ _1.title_line.strip })

    assert_index({
      "f.txt" => "six",
      "g.txt" => "eight"
    })

    assert_workspace({
      "f.txt" => "six",
      "g.txt" => "eight"
    })
  end

  def test_commit_after_conflicted_revert
    jit_cmd("revert", "@~3")
    jit_cmd("add", "g.txt")

    jit_cmd("commit")
    assert_status(0)

    commits = RevList.new(repo, ["@~3.."]).to_a
    assert_equal([commits[1].oid], commits[0].parents)

    assert_equal(['Revert "five"', "eight", "seven"],
      commits.map{ _1.title_line.strip })
  end

  def test_apply_multiple_non_conflicting_commits
    jit_cmd("revert", "@", "@^", "@^^")
    assert_status(0)

    revs = RevList.new(repo, ["@~4.."])

    assert_equal(['Revert "six"', 'Revert "seven"', 'Revert "eight"', "eight"],
      revs.map{ _1.title_line.strip })

    assert_index({
      "f.txt" => "four",
      "g.txt" => "five"
    })

    assert_workspace({
      "f.txt" => "four",
      "g.txt" => "five"
    })
  end

  def test_stop_when_list_of_commits_includes_conflict
    jit_cmd("revert", "@^", "@")
    assert_status(1)

    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UU g.txt
    EOF
  end

  def test_stop_when_range_of_commits_includes_conflict
    jit_cmd("revert", "@~5..@~2")
    assert_status(1)

    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UD g.txt
    EOF
  end

  def test_refuse_to_commit_conflicted_state
    jit_cmd("revert", "@~5..@~2")
    jit_cmd("commit")

    assert_status(128)

    assert_stderr <<~EOF
      error: Committing is not possible because you have unmerged files.
      hint: Fix them up in the work tree, and then use 'jit add/rm <file>'
      hint: as appropriate to mark resolution and make a commit.
      fatal: Exiting because of an unresolved conflict.
    EOF
  end

  def test_refuse_to_continue_conflicted_state
    jit_cmd("revert", "@~5..@~2")
    jit_cmd("revert", "--continue")

    assert_status(128)

    assert_stderr <<~EOF
      error: Committing is not possible because you have unmerged files.
      hint: Fix them up in the work tree, and then use 'jit add/rm <file>'
      hint: as appropriate to mark resolution and make a commit.
      fatal: Exiting because of an unresolved conflict.
    EOF
  end

  def test_continue_after_resolving_conflicts
    jit_cmd("revert", "@~4..@^")

    write_file("g.txt", "five")
    jit_cmd("add", "g.txt")

    jit_cmd("revert", "--continue")
    assert_status(0)

    revs = RevList.new(repo, ["@~4.."])

    assert_equal(['Revert "five"', 'Revert "six"', 'Revert "seven"', "eight"],
      revs.map{ _1.title_line.strip })

    assert_index({"f.txt" => "four"})
    assert_workspace({"f.txt" => "four"})
  end

  def test_continue_after_committing_resolved_tree
    jit_cmd("revert", "@~4..@^")

    write_file("g.txt", "five")
    jit_cmd("add", "g.txt")
    jit_cmd("commit")

    jit_cmd("revert", "--continue")
    assert_status(0)

    revs = RevList.new(repo, ["@~4.."])

    assert_equal(['Revert "five"', 'Revert "six"', 'Revert "seven"', "eight"],
      revs.map{ _1.title_line.strip })

    assert_index({"f.txt" => "four"})
    assert_workspace({"f.txt" => "four"})
  end
end

class Command::TestRevertAbortConflicted < Command::TestRevert
  def setup
    super

    jit_cmd("revert", "@~5..@^")
    jit_cmd("revert", "--abort")
  end

  def test_exit_successfully
    assert_status(0)
    assert_stderr("")
  end

  def test_reset_old_head
    assert_equal("eight", load_commit("HEAD").message.strip)

    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end

  def test_remove_merge_state
    refute(repo.pending_commit.in_progress?)
  end
end

class Command::TestRevertAbortCommitted < Command::TestRevert
  def setup
    super

    jit_cmd("revert", "@~5..@^")
    jit_cmd("add", ".")
    stub_editor("reverted\n") { jit_cmd("commit") }

    jit_cmd("revert", "--abort")
  end

  def test_exit_with_warning
    assert_status(0)
    assert_stderr <<~EOF
      warning: You seem to have moved HEAD. Not rewinding, check your HEAD!
    EOF
  end

  def test_do_not_reset_old_head
    assert_equal("reverted", load_commit("HEAD").message.strip)

    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end

  def test_remove_merge_state
    refute(repo.pending_commit.in_progress?)
  end
end
