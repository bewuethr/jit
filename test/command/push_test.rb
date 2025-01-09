require "minitest/autorun"
require "fileutils"
require "find"

require_relative "../command_helper"
require_relative "../remote_repo"

require "rev_list"

ENV["NO_PROGRESS"] = "1"

class Command::TestPush < Minitest::Test
  include CommandHelper

  def create_remote_repo(name)
    RemoteRepo.new(name).tap do |repo|
      repo.jit_cmd("init", repo.repo_path.to_s)
      repo.jit_cmd("config", "receive.denyCurrentBranch", "false")
      repo.jit_cmd("config", "receive.denyDeleteCurrent", "false")
    end
  end

  def write_commit(message)
    write_file("#{message}.txt", message)
    jit_cmd("add", ".")
    jit_cmd("commit", "-m", message)
  end

  def commits(repo, revs, options = {})
    RevList.new(repo, revs, options).map { repo.database.short_oid(_1.oid) }
  end

  def assert_object_count(n)
    count = 0
    Find.find(@remote.repo_path.join(".git", "objects")) do |path|
      count += 1 if File.file?(path)
    end
    assert_equal(n, count)
  end

  def assert_refs(repo, refs)
    assert_equal(refs, repo.refs.list_all_refs.map(&:path).sort)
  end

  def assert_workspace(contents) = super(contents, @remote.repo)

  def jit_path = File.expand_path("../../../bin/jit", __FILE__)
end

class Command::TestPushSingleBranchLocalBase < Command::TestPush
  def setup
    super

    @remote = create_remote_repo("push-remote")

    %w[one dir/two three].each { write_commit(_1) }

    jit_cmd("remote", "add", "origin", "file://#{@remote.repo_path}")
    jit_cmd("config", "remote.origin.receivepack", "#{jit_path} receive-pack")
    jit_cmd("config", "remote.origin.uploadpack", "#{jit_path} upload-pack")
  end

  def teardown
    super

    FileUtils.rm_rf(@remote.repo_path)
  end
end

class Command::TestPushSingleBranchLocal < Command::TestPushSingleBranchLocalBase
  def test_display_new_branch_being_pushed
    jit_cmd("push", "origin", "main")
    assert_status(0)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       * [new branch] main -> main
    EOF
  end

  def test_map_local_head_to_remote
    jit_cmd("push", "origin", "main")

    assert_equal(repo.refs.read_ref("refs/heads/main"),
      @remote.repo.refs.read_ref("refs/heads/main"))
  end

  def test_map_local_head_to_different_remote_ref
    jit_cmd("push", "origin", "main:refs/heads/other")

    assert_equal(repo.refs.read_ref("refs/heads/main"),
      @remote.repo.refs.read_ref("refs/heads/other"))
  end

  def test_do_not_create_other_remote_refs
    jit_cmd("push", "origin", "main")

    assert_refs(@remote.repo, ["HEAD", "refs/heads/main"])
  end

  def test_send_all_commits_from_local_history
    jit_cmd("push", "origin", "main")

    assert_equal(commits(repo, ["main"]), commits(@remote.repo, ["main"]))
  end

  def test_send_senough_information_to_check_out_local_commits
    jit_cmd("push", "origin", "main")

    @remote.jit_cmd("reset", "--hard")

    @remote.jit_cmd("checkout", "main")
    assert_workspace({
      "one.txt" => "one",
      "dir/two.txt" => "dir/two",
      "three.txt" => "three"
    })

    @remote.jit_cmd("checkout", "main^^")
    assert_workspace("one.txt" => "one")
  end

  def test_push_ancestor_of_current_head
    jit_cmd("push", "origin", "@~1:main")

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       * [new branch] @~1 -> main
    EOF

    assert_equal(commits(repo, ["main^"]), commits(@remote.repo, ["main"]))
  end
end

class Command::TestPushSingleBranchLocalAfterSuccessfulPush < Command::TestPushSingleBranchLocalBase
  def setup
    super

    jit_cmd("push", "origin", "main")
  end

  def test_say_everything_is_up_to_date
    jit_cmd("push", "origin", "main")
    assert_status(0)

    assert_stderr <<~EOF
      Everything up-to-date
    EOF

    assert_refs(@remote.repo, ["HEAD", "refs/heads/main"])

    assert_equal(repo.refs.read_ref("refs/heads/main"),
      @remote.repo.refs.read_ref("refs/heads/main"))
  end

  def test_delete_remote_branch_by_refspec
    jit_cmd("push", "origin", ":main")
    assert_status(0)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       - [deleted] main
    EOF

    assert_refs(repo, ["HEAD", "refs/heads/main"])
    assert_refs(@remote.repo, ["HEAD"])
  end
end

class Command::TestPushSingleBranchLocalWhenLocalIsAhead < Command::TestPushSingleBranchLocalBase
  def setup
    super

    jit_cmd("push", "origin", "main")

    write_file("one.txt", "changed")
    jit_cmd("add", ".")
    jit_cmd("commit", "-m", "changed")

    @local_head = commits(repo, ["main"]).first
    @remote_head = commits(@remote.repo, ["main"]).first
  end

  def test_display_fast_forward_on_changed_branch
    jit_cmd("push", "origin", "main")
    assert_status(0)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
         #{@remote_head}..#{@local_head} main -> main
    EOF
  end

  def test_succeed_when_remote_denies_fast_forward
    jit_cmd("config", "receive.denyNonFastForwards", "true")

    jit_cmd("push", "origin", "main")
    assert_status(0)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
         #{@remote_head}..#{@local_head} main -> main
    EOF
  end

  def test_reject_push_to_invalid_refname
    jit_cmd("push", "origin", "main:refs/heads/../a")
    assert_status(1)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       ! [rejected] main -> ../a (funny refname)
    EOF
  end
end

class Command::TestPushSingleBranchLocalWhenRemoteHasDivergedBase < Command::TestPushSingleBranchLocalBase
  def setup
    super

    jit_cmd("push", "origin", "main")

    @remote.write_file("one.txt", "changed")
    @remote.jit_cmd("add", ".")
    @remote.jit_cmd("commit", "--amend")

    @local_head = commits(repo, ["main"]).first
    @remote_head = commits(@remote.repo, ["main"]).first
  end
end

class Command::TestPushSingleBranchLocalWhenRemoteHasDiverged < Command::TestPushSingleBranchLocalWhenRemoteHasDivergedBase
  def test_display_forced_updated_if_requested
    jit_cmd("push", "origin", "main", "-f")
    assert_status(0)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       + #{@remote_head}...#{@local_head} main -> main (forced update)
    EOF
  end

  def test_update_local_origin_ref
    jit_cmd("push", "origin", "main", "-f")
    assert_equal(@local_head, commits(repo, ["origin/main"]).first)
  end

  def test_delete_remote_branch_by_refspec
    jit_cmd("push", "origin", ":main")
    assert_status(0)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       - [deleted] main
    EOF

    assert_refs(repo, ["HEAD", "refs/heads/main"])
    assert_refs(@remote.repo, ["HEAD"])
  end
end

class Command::TestPushIfPushIsNotForced < Command::TestPushSingleBranchLocalWhenRemoteHasDivergedBase
  def setup
    super

    jit_cmd("push", "origin", "main")
  end

  def test_exit_with_error
    assert_status(1)
  end

  def test_tell_user_to_fetch_before_pushing
    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       ! [rejected] main -> main (fetch first)
    EOF
  end

  def test_display_rejection_after_fetching
    jit_cmd("fetch")
    jit_cmd("push", "origin", "main")

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       ! [rejected] main -> main (non-fast-forward)
    EOF
  end

  def test_doest_not_update_local_origin_ref
    refute_equal(@remote_head, @local_head)
    assert_equal(@local_head, commits(repo, ["origin/main"]).first)
  end
end

class Command::TestPushRemoteDeniesNonFastForward < Command::TestPushSingleBranchLocalWhenRemoteHasDivergedBase
  def setup
    super

    @remote.jit_cmd("config", "receive.denyNonFastForwards", "true")
    jit_cmd("fetch")
  end

  def test_reject_pushed_update
    jit_cmd("push", "origin", "main", "-f")
    assert_status(1)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       ! [rejected] main -> main (non-fast-forward)
    EOF
  end
end

class Command::TestPushRemoteDeniesUpdatingCurrentBranch < Command::TestPushSingleBranchLocalBase
  def setup
    super

    @remote.jit_cmd("config", "--unset", "receive.denyCurrentBranch")
  end

  def test_reject_pushed_update
    jit_cmd("push", "origin", "main")
    assert_status(1)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       ! [rejected] main -> main (branch is currently checked out)
    EOF
  end

  def test_do_not_update_remote_refs
    jit_cmd("push", "origin", "main")

    refute_nil(repo.refs.read_ref("refs/heads/main"))
    assert_nil(@remote.repo.refs.read_ref("refs/heads/main"))
  end

  def test_do_not_udpate_local_remote_ref
    jit_cmd("push", "origin", "main")

    assert_nil(@remote.repo.refs.read_ref("refs/remotes/origin/main"))
  end
end

class Command::TestPushRemoteDeniesDeletingCurrentBranch < Command::TestPushSingleBranchLocalBase
  def setup
    super

    jit_cmd("push", "origin", "main")
    @remote.jit_cmd("config", "--unset", "receive.denyDeleteCurrent")
  end

  def test_reject_pushed_update
    jit_cmd("push", "origin", ":main")
    assert_status(1)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       ! [rejected] main (deletion of the current branch prohibited)
    EOF
  end

  def test_do_not_delete_remote_refs
    jit_cmd("push", "origin", ":main")

    refute_nil(@remote.repo.refs.read_ref("refs/heads/main"))
  end

  def test_do_not_udpate_local_remote_ref
    jit_cmd("push", "origin", ":main")

    refute_nil(repo.refs.read_ref("refs/remotes/origin/main"))
  end
end

class Command::TestPushRemoteDeniesDeletingAnytBranch < Command::TestPushSingleBranchLocalBase
  def setup
    super

    jit_cmd("push", "origin", "main")
    @remote.jit_cmd("config", "receive.denyDeletes", "true")
  end

  def test_reject_pushed_update
    jit_cmd("push", "origin", ":main")
    assert_status(1)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       ! [rejected] main (deletion prohibited)
    EOF
  end

  def test_do_not_delete_remote_refs
    jit_cmd("push", "origin", ":main")

    refute_nil(@remote.repo.refs.read_ref("refs/heads/main"))
  end

  def test_do_not_udpate_local_remote_ref
    jit_cmd("push", "origin", ":main")

    refute_nil(repo.refs.read_ref("refs/remotes/origin/main"))
  end
end

class Command::TestPushMultipleBranchesLocalBase < Command::TestPush
  def setup
    super

    @remote = create_remote_repo("push-remote")

    %w[one dir/two three].each { write_commit(_1) }

    jit_cmd("branch", "topic", "@^")
    jit_cmd("checkout", "topic")
    write_commit("four")

    jit_cmd("remote", "add", "origin", "file://#{@remote.repo_path}")
    jit_cmd("config", "remote.origin.receivepack", "#{jit_path} receive-pack")
  end

  def teardown
    super

    FileUtils.rm_rf(@remote.repo_path)
  end
end

class Command::TestPushMultipleBranchesLocal < Command::TestPushMultipleBranchesLocalBase
  def test_display_new_branches_being_pushed
    jit_cmd("push", "origin", "refs/heads/*")
    assert_status(0)

    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       * [new branch] main -> main
       * [new branch] topic -> topic
    EOF
  end

  def test_map_local_heads_to_remote_heads
    jit_cmd("push", "origin", "refs/heads/*")

    local_main = repo.refs.read_ref("refs/heads/main")
    local_topic = repo.refs.read_ref("refs/heads/topic")

    refute_equal(local_main, local_topic)
    assert_equal(local_main, @remote.repo.refs.read_ref("refs/heads/main"))
    assert_equal(local_topic, @remote.repo.refs.read_ref("refs/heads/topic"))
  end

  def test_map_local_heads_to_different_remote_ref
    jit_cmd("push", "origin", "refs/heads/*:refs/other/*")

    assert_equal(repo.refs.read_ref("refs/heads/main"),
      @remote.repo.refs.read_ref("refs/other/main"))

    assert_equal(repo.refs.read_ref("refs/heads/topic"),
      @remote.repo.refs.read_ref("refs/other/topic"))
  end

  def test_do_not_create_other_remote_refs
    jit_cmd("push", "origin", "refs/heads/*")

    assert_refs(@remote.repo, ["HEAD", "refs/heads/main", "refs/heads/topic"])
  end

  def test_send_all_commits_from_local_history
    jit_cmd("push", "origin", "refs/heads/*")
    assert_object_count(13)

    local_commits = commits(repo, ["main", "topic"])
    assert_equal(4, local_commits.size)

    assert_equal(local_commits, commits(@remote.repo, ["main", "topic"]))
  end

  def test_send_senough_information_to_check_out_local_commits
    jit_cmd("push", "origin", "refs/heads/*")

    @remote.jit_cmd("reset", "--hard")

    @remote.jit_cmd("checkout", "main")
    assert_workspace({
      "one.txt" => "one",
      "dir/two.txt" => "dir/two",
      "three.txt" => "three"
    })

    @remote.jit_cmd("checkout", "topic")
    assert_workspace({
      "one.txt" => "one",
      "dir/two.txt" => "dir/two",
      "four.txt" => "four"
    })
  end
end

class Command::TestPushMultipleWhenSpecificBranchIsPushed < Command::TestPushMultipleBranchesLocalBase
  def setup
    super

    jit_cmd("push", "origin", "refs/heads/*ic:refs/heads/*")
  end

  def test_display_branch_being_pushed
    assert_stderr <<~EOF
      To file://#{@remote.repo_path}
       * [new branch] topic -> top
    EOF
  end

  def test_do_not_create_other_local_refs
    assert_refs(@remote.repo, ["HEAD", "refs/heads/top"])
  end

  def test_retrieve_only_commits_from_fetched_branch
    assert_object_count(10)

    local_commits = commits(repo, ["topic"])
    assert_equal(3, local_commits.size)

    assert_equal(local_commits, commits(@remote.repo, [], all: true))
  end
end

class Command::TestPushMultipleWhenReceiverHasStoredPack < Command::TestPushMultipleBranchesLocalBase
  def setup
    super

    @alice = create_remote_repo("push-remote-alice")
    @bob = create_remote_repo("push-remote-bob")

    @alice.jit_cmd("config", "receive.unpackLimit", "5")

    %w[one dir/two three].each { write_commit(it) }

    jit_cmd("remote", "add", "alice", "file://#{@alice.repo_path}")
    jit_cmd("config", "remote.alice.receivepack", "#{jit_path} receive-pack")

    jit_cmd("push", "alice", "refs/heads/*")
  end

  def teardown
    super

    FileUtils.rm_rf(@alice.repo_path)
    FileUtils.rm_rf(@bob.repo_path)
  end

  def test_push_packed_objects_to_other_repository
    @alice.jit_cmd("remote", "add", "bob", "file://#{@bob.repo_path}")
    @alice.jit_cmd("config", "remote.bob.receivepack", "#{jit_path} receive-pack")

    @alice.jit_cmd("push", "bob", "refs/heads/*")

    assert_equal(commits(repo, ["main"]), commits(@bob.repo, ["main"]))
  end
end
