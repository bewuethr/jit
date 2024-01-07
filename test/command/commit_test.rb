require "minitest/autorun"

require_relative "../command_helper"

class Command::TestCommit < Minitest::Test
  include CommandHelper

  def commit_change(content)
    write_file("file.txt", content)
    jit_cmd("add", ".")
    commit(content)
  end

  def setup
    super

    ["first", "second", "third"].each do |message|
      commit_change(message)

      jit_cmd("branch", "topic")
      jit_cmd("checkout", "topic")
    end
  end
end

class Command::TestCommitOnBranch < Command::TestCommit
  def test_advance_branch_pointer
    head_before = repo.refs.read_ref("HEAD")

    commit_change("change")

    head_after = repo.refs.read_ref("HEAD")
    branch_after = repo.refs.read_ref("topic")

    refute_equal(head_before, head_after)
    assert_equal(head_after, branch_after)

    assert_equal(head_before, resolve_revision("@^"))
  end
end

class Command::TestCommitWithDetachedHead < Command::TestCommit
  def setup
    super

    jit_cmd("checkout", "@")
  end

  def test_advance_head
    head_before = repo.refs.read_ref("HEAD")
    commit_change("change")
    head_after = repo.refs.read_ref("HEAD")

    refute_equal(head_before, head_after)
  end

  def test_not_advance_detached_branch
    branch_before = repo.refs.read_ref("topic")
    commit_change("change")
    branch_after = repo.refs.read_ref("topic")

    assert_equal(branch_before, branch_after)
  end

  def test_leave_head_ahead_of_branch
    commit_change("change")

    assert_equal(repo.refs.read_ref("topic"), resolve_revision("@^"))
  end
end

class Command::TestCommitWithConcurrentBranches < Command::TestCommit
  def setup
    super

    jit_cmd("branch", "fork", "@^")
  end

  def test_advance_branch_from_shared_parent
    commit_change("A")
    commit_change("B")

    jit_cmd("checkout", "fork")
    commit_change("C")

    refute_equal(resolve_revision("topic"), resolve_revision("fork"))
    assert_equal(resolve_revision("topic~3"), resolve_revision("fork^"))
  end
end
