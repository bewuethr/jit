require "minitest/autorun"

require_relative "../command_helper"

class Command::TestBranch < Minitest::Test
  include CommandHelper

  def write_commit(message)
    write_file("file.txt", message)
    jit_cmd("add", ".")
    commit(message)
  end

  def setup
    super

    %w[first second third].each { write_commit(it) }
  end
end

class Command::TestBranchWithChainOfCommits < Command::TestBranch
  def test_create_branch_pointing_at_head
    jit_cmd("branch", "feature")
    assert_equal(repo.refs.read_head, repo.refs.read_ref("feature"))
  end

  def test_prevent_invalid_branch_names
    [
      ".dot",
      "slash/.dot",
      "dot..dot",
      "/slashstart",
      "slashend/",
      "name.lock",
      "feature@{something}",
      "a space",
      "ast*erisk",
      "col:on",
      "quest?ionmark",
      "brac[ket"
    ].each do |name|
      jit_cmd("branch", name)

      assert_status(128)
      assert_stderr("fatal: '#{name}' is not a valid branch name.\n")
    end
  end

  def test_prevent_duplicate_branch_creation
    jit_cmd("branch", "feature")
    jit_cmd("branch", "feature")

    assert_status(128)
    assert_stderr("fatal: A branch named 'feature' already exists.\n")
  end

  def test_create_branch_pointing_at_head_parent
    jit_cmd("branch", "feature", "HEAD^")

    head = repo.database.load(repo.refs.read_head)

    assert_equal(head.parent, repo.refs.read_ref("feature"))
  end

  def test_create_branch_pointing_at_head_grandparent
    jit_cmd("branch", "feature", "@~2")

    head = repo.database.load(repo.refs.read_head)
    parent = repo.database.load(head.parent)

    assert_equal(parent.parent, repo.refs.read_ref("feature"))
  end

  def test_create_branch_relative_to_other_branch
    jit_cmd("branch", "feature", "@~1")
    jit_cmd("branch", "other", "feature^")

    assert_equal(resolve_revision("HEAD~2"), repo.refs.read_ref("other"))
  end

  def test_create_branch_from_short_commit_id
    commit_id = resolve_revision("@~2")
    jit_cmd("branch", "feature", repo.database.short_oid(commit_id))

    assert_equal(commit_id, repo.refs.read_ref("feature"))
  end

  def test_fail_for_invalid_revision
    jit_cmd("branch", "feature", "^")

    assert_stderr("fatal: Not a valid object name: '^'.\n")
  end

  def test_fail_for_invalid_ref
    jit_cmd("branch", "feature", "does-not-exist")

    assert_stderr("fatal: Not a valid object name: 'does-not-exist'.\n")
  end

  def test_fail_for_invalid_parent
    jit_cmd("branch", "feature", "@^^^")

    assert_stderr("fatal: Not a valid object name: '@^^^'.\n")
  end

  def test_fail_for_invalid_ancestor
    jit_cmd("branch", "feature", "@~5")

    assert_stderr("fatal: Not a valid object name: '@~5'.\n")
  end

  def test_fail_for_non_commit_revision
    tree_id = repo.database.load(repo.refs.read_head).tree
    jit_cmd("branch", "feature", tree_id)

    assert_stderr <<~EOF
      error: object #{tree_id} is a tree, not a commit
      fatal: Not a valid object name: '#{tree_id}'.
    EOF
  end

  def test_fail_for_parent_of_non_commit_revision
    tree_id = repo.database.load(repo.refs.read_head).tree
    jit_cmd("branch", "feature", "#{tree_id}^")

    assert_stderr <<~EOF
      error: object #{tree_id} is a tree, not a commit
      fatal: Not a valid object name: '#{tree_id}^'.
    EOF
  end

  def test_list_existing_branches
    jit_cmd("branch", "new-feature")
    jit_cmd("branch")

    assert_stdout <<~EOF
      * main
        new-feature
    EOF
  end

  def test_list_existing_branches_verbose
    a = load_commit("@^")
    b = load_commit("@")

    jit_cmd("branch", "new-feature", "@^")
    jit_cmd("branch", "--verbose")

    assert_stdout <<~EOF
      * main        #{repo.database.short_oid(b.oid)} third
        new-feature #{repo.database.short_oid(a.oid)} second
    EOF
  end

  def test_delete_branch
    head = repo.refs.read_head

    jit_cmd("branch", "bug-fix")
    jit_cmd("branch", "--delete", "bug-fix")

    assert_stdout <<~EOF
      Deleted branch bug-fix (was #{repo.database.short_oid(head)}).
    EOF

    branches = repo.refs.list_branches
    refute_includes(branches.map(&:short_name), "bug-fix")
  end

  def test_fail_to_delete_non_existent_branch
    jit_cmd("branch", "--delete", "no-such-branch")

    assert_status(1)

    assert_stderr <<~EOF
      error: branch 'no-such-branch' not found.
    EOF
  end
end

class Command::TestBranchWhenDiverged < Command::TestBranch
  def setup
    super

    jit_cmd("branch", "topic")
    jit_cmd("checkout", "topic")

    write_commit("changed")

    jit_cmd("checkout", "main")
  end

  def test_delete_merged_branch
    head = repo.refs.read_head

    jit_cmd("checkout", "topic")
    jit_cmd("branch", "--delete", "main")
    assert_status(0)

    assert_stdout <<~EOF
      Deleted branch main (was #{repo.database.short_oid(head)}).
    EOF
  end

  def test_refuse_to_delete_branch
    jit_cmd("branch", "--delete", "topic")
    assert_status(1)

    assert_stderr <<~EOF
      error: The branch 'topic' is not fully merged.
    EOF
  end

  def test_delete_branch_with_force
    head = repo.refs.read_ref("topic")

    jit_cmd("branch", "-D", "topic")
    assert_status(0)

    assert_stdout <<~EOF
      Deleted branch topic (was #{repo.database.short_oid(head)}).
    EOF
  end
end
