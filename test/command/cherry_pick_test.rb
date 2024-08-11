require "minitest/autorun"

require_relative "../command_helper"

require "rev_list"

class Command::TestCherryPick < Minitest::Test
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
end

class Command::TestCherryPickBranches < Command::TestCherryPick
  def setup
    super

    ["one", "two", "three", "four"].each do |message|
      commit_tree(message, {"f.txt" => message})
    end

    jit_cmd("branch", "topic", "@~2")
    jit_cmd("checkout", "topic")

    commit_tree("five", {"g.txt" => "five"})
    commit_tree("six", {"f.txt" => "six"})
    commit_tree("seven", {"g.txt" => "seven"})
    commit_tree("eight", {"g.txt" => "eight"})

    jit_cmd("checkout", "main")
  end
end

class Command::TestCherryPickTwoBranches < Command::TestCherryPickBranches
  def test_apply_commit_on_top_of_current_head
    jit_cmd("cherry-pick", "topic~3")
    assert_status(0)

    revs = RevList.new(repo, ["@~3.."])

    assert_equal(["five", "four", "three"], revs.map { _1.message.strip })

    assert_index({
      "f.txt" => "four",
      "g.txt" => "five"
    })

    assert_workspace({
      "f.txt" => "four",
      "g.txt" => "five"
    })
  end

  def test_fail_to_apply_a_content_conflict
    jit_cmd("cherry-pick", "topic^^")
    assert_status(1)

    short = repo.database.short_oid(resolve_revision("topic^^"))

    assert_workspace({
      "f.txt" => <<~EOF
        <<<<<<< HEAD
        four=======
        six>>>>>>> #{short}... six
      EOF
    })

    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UU f.txt
    EOF
  end

  def test_fail_to_apply_a_modify_delete_conflict
    jit_cmd("cherry-pick", "topic")
    assert_status(1)

    assert_workspace({
      "f.txt" => "four",
      "g.txt" => "eight"
    })

    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      DU g.txt
    EOF
  end

  def test_continue_conflicted_cherry_pick
    jit_cmd("cherry-pick", "topic")
    jit_cmd("add", "g.txt")

    jit_cmd("cherry-pick", "--continue")
    assert_status(0)

    commits = RevList.new(repo, ["@~3.."]).to_a
    assert_equal([commits[1].oid], commits[0].parents)

    assert_equal(["eight", "four", "three"], commits.map { _1.message.strip })

    assert_index({
      "f.txt" => "four",
      "g.txt" => "eight"
    })

    assert_workspace({
      "f.txt" => "four",
      "g.txt" => "eight"
    })
  end

  def test_commit_after_conflicted_cherry_pick
    jit_cmd("cherry-pick", "topic")
    jit_cmd("add", "g.txt")

    jit_cmd("commit")
    assert_status(0)

    commits = RevList.new(repo, ["@~3.."]).to_a
    assert_equal([commits[1].oid], commits[0].parents)

    assert_equal(["eight", "four", "three"], commits.map { _1.message.strip })
  end

  def test_apply_multiple_non_conflicting_commits
    jit_cmd("cherry-pick", "topic~3", "topic^", "topic")
    assert_status(0)

    revs = RevList.new(repo, ["@~4.."])
    assert_equal(["eight", "seven", "five", "four"], revs.map { _1.message.strip })

    assert_index({
      "f.txt" => "four",
      "g.txt" => "eight"
    })

    assert_workspace({
      "f.txt" => "four",
      "g.txt" => "eight"
    })
  end

  def test_stop_when_commit_list_includes_conflict
    jit_cmd("cherry-pick", "topic^", "topic~3")
    assert_status(1)

    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      DU g.txt
    EOF
  end

  def test_stop_when_commit_range_includes_conflict
    jit_cmd("cherry-pick", "..topic")
    assert_status(1)

    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UU f.txt
    EOF
  end

  def test_refuse_committing_in_conflicted_state
    jit_cmd("cherry-pick", "..topic")
    jit_cmd("commit")

    assert_status(128)

    assert_stderr <<~EOF
      error: Committing is not possible because you have unmerged files.
      hint: Fix them up in the work tree, and then use 'jit add/rm <file>'
      hint: as appropriate to mark resolution and make a commit.
      fatal: Exiting because of an unresolved conflict.
    EOF
  end

  def test_refuse_continuing_in_conflicted_state
    jit_cmd("cherry-pick", "..topic")
    jit_cmd("cherry-pick", "--continue")

    assert_status(128)

    assert_stderr <<~EOF
      error: Committing is not possible because you have unmerged files.
      hint: Fix them up in the work tree, and then use 'jit add/rm <file>'
      hint: as appropriate to mark resolution and make a commit.
      fatal: Exiting because of an unresolved conflict.
    EOF
  end

  def test_continue_after_resolving_conflicts
    jit_cmd("cherry-pick", "..topic")

    write_file("f.txt", "six")
    jit_cmd("add", "f.txt")

    jit_cmd("cherry-pick", "--continue")
    assert_status(0)

    revs = RevList.new(repo, ["@~5.."])

    assert_equal(["eight", "seven", "six", "five", "four"],
      revs.map { _1.message.strip })

    assert_index({
      "f.txt" => "six",
      "g.txt" => "eight"
    })

    assert_workspace({
      "f.txt" => "six",
      "g.txt" => "eight"
    })
  end

  def test_continue_after_committing_resolved_tree
    jit_cmd("cherry-pick", "..topic")

    write_file("f.txt", "six")
    jit_cmd("add", "f.txt")
    jit_cmd("commit")

    jit_cmd("cherry-pick", "--continue")
    assert_status(0)

    revs = RevList.new(repo, ["@~5.."])

    assert_equal(["eight", "seven", "six", "five", "four"],
      revs.map { _1.message.strip })

    assert_index({
      "f.txt" => "six",
      "g.txt" => "eight"
    })

    assert_workspace({
      "f.txt" => "six",
      "g.txt" => "eight"
    })
  end
end

class Command::TestCherryPickAbortInConflictedState < Command::TestCherryPickBranches
  def setup
    super

    jit_cmd("cherry-pick", "..topic")
    jit_cmd("cherry-pick", "--abort")
  end

  def test_exit_successfully
    assert_status(0)
    assert_stderr("")
  end

  def test_reset_to_old_head
    assert_equal("four", load_commit("HEAD").message.strip)

    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end

  def test_remove_merge_state = refute(repo.pending_commit.in_progress?)
end

class Command::TestCherryPickAbortInCommittedState < Command::TestCherryPickBranches
  def setup
    super

    jit_cmd("cherry-pick", "..topic")
    jit_cmd("add", ".")
    stub_editor("picked\n") { jit_cmd("commit") }

    jit_cmd("cherry-pick", "--abort")
  end

  def test_exit_with_warning
    assert_status(0)
    assert_stderr <<~EOF
      warning: You seem to have moved HEAD. Not rewinding, check your HEAD!
    EOF
  end

  def test_do_not_reset_head
    assert_equal("picked", load_commit("HEAD").message.strip)

    jit_cmd("status", "--porcelain")
    assert_stdout("")
  end

  def test_remove_merge_state = refute(repo.pending_commit.in_progress?)
end

class Command::TestCherryPickMerges < Command::TestCherryPick
  #   f---f---f---f [main]
  #        \
  #         g---h---o---o [topic]
  #          \     /   /
  #           j---j---f [side]
  def setup
    super

    %w[one two three four].each do |message|
      commit_tree(message, "f.txt" => message)
    end

    jit_cmd("branch", "topic", "@~2")
    jit_cmd("checkout", "topic")
    commit_tree("five", "g.txt" => "five")
    commit_tree("six", "h.txt" => "six")

    jit_cmd("branch", "side", "@^")
    jit_cmd("checkout", "side")
    commit_tree("seven", "j.txt" => "seven")
    commit_tree("eight", "j.txt" => "eight")
    commit_tree("nine", "f.txt" => "nine")

    jit_cmd("checkout", "topic")
    jit_cmd("merge", "side^", "-m", "merge side^")
    jit_cmd("merge", "side", "-m", "merge side")

    jit_cmd("checkout", "main")
  end

  def test_refuse_cherry_pick_merge_without_specifying_parent
    jit_cmd("cherry-pick", "topic")
    assert_status(1)

    oid = resolve_revision("topic")

    assert_stderr <<~EOF
      error: commit #{oid} is a merge but no -m option was given
    EOF
  end

  def test_refuse_cherry_pick_non_merge_with_mainline
    jit_cmd("cherry-pick", "-m", "1", "side")
    assert_status(1)

    oid = resolve_revision("side")

    assert_stderr <<~EOF
      error: mainline was specified but commit #{oid} is not a merge
    EOF
  end

  def test_cherry_pick_merge_based_on_first_parent
    jit_cmd("cherry-pick", "-m", "1", "topic^")
    assert_status(0)

    assert_index({
      "f.txt" => "four",
      "j.txt" => "eight"
    })

    assert_workspace({
      "f.txt" => "four",
      "j.txt" => "eight"
    })
  end

  def test_cherry_pick_merge_based_on_second_parent
    jit_cmd("cherry-pick", "-m", "2", "topic^")
    assert_status(0)

    assert_index({
      "f.txt" => "four",
      "h.txt" => "six"
    })

    assert_workspace({
      "f.txt" => "four",
      "h.txt" => "six"
    })
  end

  def test_resume_cherry_picking_merge_after_conflict
    jit_cmd("cherry-pick", "-m", "1", "topic", "topic^")
    assert_status(1)

    jit_cmd("status", "--porcelain")

    assert_stdout <<~EOF
      UU f.txt
    EOF

    write_file("f.txt", "resolved")
    jit_cmd("add", "f.txt")
    jit_cmd("cherry-pick", "--continue")
    assert_status(0)

    revs = RevList.new(repo, ["@~3.."])

    assert_equal(["merge side^", "merge side", "four"],
      revs.map { _1.message.strip })

    assert_index({
      "f.txt" => "resolved",
      "j.txt" => "eight"
    })

    assert_workspace({
      "f.txt" => "resolved",
      "j.txt" => "eight"
    })
  end
end
