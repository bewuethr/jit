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
end
