require "minitest/autorun"

require_relative "../command_helper"

require "rev_list"

class Command::TestCherryPick < Minitest::Test
  include CommandHelper

  def commit_tree(message, files)
    files.each do |path, contents|
      write_file(path, contents)
    end
    jit_cmd("add", ".")
    commit(message)
  end
end

class Command::TestCherryPickWithTwoBranches < Command::TestCherryPick
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
end
