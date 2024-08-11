require "minitest/autorun"

require_relative "../command_helper"

require "rev_list"

class Command::TestCommit < Minitest::Test
  include CommandHelper
end

class Command::TestCommitToBranches < Command::TestCommit
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

class Command::TestCommitOnBranch < Command::TestCommitToBranches
  def setup
    super
  end

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

class Command::TestCommitWithDetachedHead < Command::TestCommitToBranches
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

class Command::TestCommitWithConcurrentBranches < Command::TestCommitToBranches
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

class Command::TestCommitConfiguringAuthor < Command::TestCommit
  def setup
    super

    jit_cmd("config", "user.name", "A. N. User")
    jit_cmd("config", "user.email", "user@example.com")
  end

  def test_use_author_info_from_config
    write_file("file.txt", "1")
    jit_cmd("add", ".")
    commit("first", nil, false)

    head = load_commit("@")
    assert_equal("A. N. User", head.author.name)
    assert_equal("user@example.com", head.author.email)
  end
end

class Command::TestCommitReusingMessages < Command::TestCommit
  def setup
    super

    write_file("file.txt", "1")
    jit_cmd("add", ".")
    commit("first")
  end

  def test_use_message_from_another_commit
    write_file("file.txt", "2")
    jit_cmd("add", ".")
    jit_cmd("commit", "-C", "@")

    revs = RevList.new(repo, ["HEAD"])
    assert_equal(["first", "first"], revs.map { _1.message.strip })
  end
end

class Command::TestCommitAmending < Command::TestCommit
  def setup
    super

    ["first", "second", "third"].each do |message|
      write_file("file.txt", message)
      jit_cmd("add", ".")
      commit(message)
    end
  end

  def test_replace_last_commit_message
    stub_editor("third [amended]\n") { jit_cmd("commit", "--amend") }
    revs = RevList.new(repo, ["HEAD"])

    assert_equal(["third [amended]", "second", "first"],
      revs.map { _1.message.strip })
  end

  def test_replace_last_commit_tree
    write_file("another.txt", "1")
    jit_cmd("add", "another.txt")
    jit_cmd("commit", "--amend")

    commit = load_commit("HEAD")
    diff = repo.database.tree_diff(commit.parent, commit.oid)

    assert_equal(["another.txt", "file.txt"], diff.keys.map(&:to_s).sort)
  end
end
