require "minitest/autorun"

require_relative "../command_helper"

class Command::TestBranch < Minitest::Test
  include CommandHelper

  def write_commit(message)
    write_file("file.txt", message)
    jit_cmd("add", ".")
    commit(message)
  end
end

class Command::TestBranchBase < Command::TestBranch
  def setup
    super

    %w[first second third].each { write_commit(it) }
  end
end

class Command::TestBranchWithChainOfCommits < Command::TestBranchBase
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

class Command::TestBranchWhenDiverged < Command::TestBranchBase
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

class Command::TestBranchTrackingRemotes < Command::TestBranch
  def setup
    super

    jit_cmd("remote", "add", "origin", "ssh://example.com/repo")
    @upstream = "refs/remotes/origin/main"

    %w[first second remote].each { write_commit(it) }
    repo.refs.update_ref(@upstream, repo.refs.read_head)

    jit_cmd("reset", "--hard", "@^")
    %w[third local].each { write_commit(it) }

    @head = repo.database.short_oid(repo.refs.read_head)
    @remote = repo.database.short_oid(repo.refs.read_ref(@upstream))
  end

  def test_display_no_divergence_for_unlinked_branches
    jit_cmd("branch", "--verbose")

    assert_stdout <<~EOF
      * main #{@head} local
    EOF
  end

  def test_display_divergence_for_linked_branches
    jit_cmd("branch", "--set-upstream-to", "origin/main")
    jit_cmd("branch", "--verbose")

    assert_stdout <<~EOF
      * main #{@head} [ahead 2, behind 1] local
    EOF
  end

  def test_display_branch_ahead_of_its_upstream
    repo.refs.update_ref(@upstream, resolve_revision("main~2"))

    jit_cmd("branch", "--set-upstream-to", "origin/main")
    jit_cmd("branch", "--verbose")

    assert_stdout <<~EOF
      * main #{@head} [ahead 2] local
    EOF
  end

  def test_display_branch_behind_its_upstream
    main = resolve_revision("@~2")
    oid = repo.database.short_oid(main)

    jit_cmd("reset", main)
    jit_cmd("branch", "--set-upstream-to", "origin/main")
    jit_cmd("branch", "--verbose")

    assert_stdout <<~EOF
      * main #{oid} [behind 1] second
    EOF
  end

  def test_display_current_upstream_branch_name
    jit_cmd("branch", "--set-upstream-to", "origin/main")
    jit_cmd("branch", "-vv")

    assert_stdout <<~EOF
      * main #{@head} [origin/main, ahead 2, behind 1] local
    EOF
  end

  def test_display_upstream_branch_name_with_no_divergence
    jit_cmd("reset", "--hard", "origin/main")

    jit_cmd("branch", "--set-upstream-to", "origin/main")
    jit_cmd("branch", "-vv")

    assert_stdout <<~EOF
      * main #{@remote} [origin/main] remote
    EOF
  end

  def test_fail_if_upstream_ref_does_not_exist
    jit_cmd("branch", "--set-upstream-to", "origin/nope")
    assert_status(1)

    assert_stderr <<~EOF
      error: the requested upstream branch 'origin/nope' does not exist
    EOF
  end

  def test_fail_if_upstream_remote_does_not_exist
    repo.refs.update_ref("refs/remotes/nope/main", repo.refs.read_head)

    jit_cmd("branch", "--set-upstream-to", "nope/main")
    assert_status(128)

    assert_stderr \
      "fatal: Cannot setup tracking information; " \
      "starting point 'refs/remotes/nope/main' is not a branch\n"
  end

  def test_create_branch_tracking_its_start_point
    jit_cmd("branch", "--track", "topic", "origin/main")
    jit_cmd("checkout", "topic")

    write_commit("topic")
    oid = repo.database.short_oid(repo.refs.read_head)

    jit_cmd("branch", "--verbose")

    assert_stdout <<~EOF
        main  #{@head} local
      * topic #{oid} [ahead 1] topic
    EOF
  end

  def test_unlink_branch_from_upstream
    jit_cmd("branch", "--set-upstream-to", "origin/main")
    jit_cmd("branch", "--unset-upstream")
    jit_cmd("branch", "--verbose")

    assert_stdout <<~EOF
      * main #{@head} local
    EOF
  end

  def test_resolve_upstream_revision
    jit_cmd("branch", "--set-upstream-to", "origin/main")

    refute_equal(resolve_revision("origin/main"), resolve_revision("main"))
    assert_equal(resolve_revision("origin/main"), resolve_revision("@{U}"))
    assert_equal(resolve_revision("origin/main"), resolve_revision("main@{upstream}"))
  end
end
