require "minitest/autorun"
require "fileutils"
require "find"

require_relative "../command_helper"
require_relative "../remote_repo"

require "rev_list"

class Command::TestFetch < Minitest::Test
  include CommandHelper

  def write_commit(message)
    @remote.write_file("#{message}.txt", message)
    @remote.jit_cmd("add", ".")
    @remote.jit_cmd("commit", "-m", message)
  end

  def commits(repo, revs, options = {})
    RevList.new(repo, revs, options).map { repo.database.short_oid(_1.oid) }
  end

  def assert_object_count(n)
    count = 0
    Find.find(repo_path.join(".git", "objects")) { count += 1 if File.file?(_1) }
    assert_equal(n, count)
  end

  def jit_path = File.expand_path("../../../bin/jit", __FILE__)
end

class Command::TestFetchSingleBranchInRemote < Command::TestFetch
  def setup
    super

    @remote = RemoteRepo.new("fetch-remote")
    @remote.jit_cmd("init", @remote.repo_path.to_s)

    %w[one dir/two three].each { write_commit(_1) }

    jit_cmd("remote", "add", "origin", "file://#{@remote.repo_path}")
    jit_cmd("config", "remote.origin.uploadpack", "#{jit_path} upload-pack")
  end

  def teardown
    super

    FileUtils.rm_rf(@remote.repo_path)
  end
end

class Command::TestFetchSingleBranchInRemoteBase < Command::TestFetchSingleBranchInRemote
  def test_display_new_branch_being_fetched
    jit_cmd("fetch")
    assert_status(0)

    assert_stderr <<~EOF
      From file://#{@remote.repo_path}
       * [new branch] main -> origin/main
    EOF
  end

  def test_map_remote_heads_to_different_local_ref
    jit_cmd("fetch", "origin", "refs/heads/*:refs/remotes/other/prefix-*")

    assert_equal(@remote.repo.refs.read_ref("refs/heads/main"),
      repo.refs.read_ref("refs/remotes/other/prefix-main"))
  end

  def test_not_create_other_local_refs
    jit_cmd("fetch")

    assert_equal(["HEAD", "refs/remotes/origin/main"],
      repo.refs.list_all_refs.map(&:path).sort)
  end

  def test_retrieve_all_commits_from_remote_history
    jit_cmd("fetch")

    assert_equal(commits(@remote.repo, ["main"]),
      commits(repo, ["origin/main"]))
  end

  def test_retrieve_enough_information_to_check_out_remotes_commits
    jit_cmd("fetch")
    jit_cmd("checkout", "origin/main^")
    assert_workspace({
      "one.txt" => "one",
      "dir/two.txt" => "dir/two"
    })

    jit_cmd("checkout", "origin/main")
    assert_workspace({
      "one.txt" => "one",
      "dir/two.txt" => "dir/two",
      "three.txt" => "three"
    })

    jit_cmd("checkout", "origin/main^^")
    assert_workspace("one.txt" => "one")
  end
end

class Command::TestFetchSingleBranchInRemoteRemoteAhead < Command::TestFetchSingleBranchInRemote
  def setup
    super

    jit_cmd("fetch")

    @remote.write_file("one.txt", "changed")
    @remote.jit_cmd("add", ".")
    @remote.jit_cmd("commit", "-m", "changed")

    @local_head = commits(repo, ["origin/main"]).first
    @remote_head = commits(@remote.repo, ["main"]).first
  end

  def test_display_fast_forward_on_changed_branch
    jit_cmd("fetch")
    assert_status(0)

    assert_stderr <<~EOF
      From file://#{@remote.repo_path}
         #{@local_head}..#{@remote_head} main -> origin/main
    EOF
  end
end

class Command::TestFetchSingleBranchInRemoteRemoteDiverged < Command::TestFetchSingleBranchInRemote
  def setup
    super

    jit_cmd("fetch")

    @remote.write_file("one.txt", "changed")
    @remote.jit_cmd("add", ".")
    @remote.jit_cmd("commit", "--amend")

    @local_head = commits(repo, ["origin/main"]).first
    @remote_head = commits(@remote.repo, ["main"]).first
  end
end

class Command::TestFetchSingleBranchInRemoteRemoteDivergedBase < Command::TestFetchSingleBranchInRemoteRemoteDiverged
  def test_display_forced_update_on_changed_branch
    jit_cmd("fetch")
    assert_status(0)

    assert_stderr <<~EOF
      From file://#{@remote.repo_path}
       + #{@local_head}...#{@remote_head} main -> origin/main (forced update)
    EOF
  end

  def test_display_forced_update_if_requested
    jit_cmd("fetch", "-f", "origin", "refs/heads/*:refs/remotes/origin/*")
    assert_status(0)

    assert_stderr <<~EOF
      From file://#{@remote.repo_path}
       + #{@local_head}...#{@remote_head} main -> origin/main (forced update)
    EOF
  end

  def test_update_local_ref
    jit_cmd("fetch")

    refute_equal(@remote_head, @local_head)
    assert_equal(@remote_head, commits(repo, ["origin/main"]).first)
  end
end

class Command::TestFetchSingleBranchInRemoteRemoteDivergedFetchNotForced < Command::TestFetchSingleBranchInRemoteRemoteDiverged
  def setup
    super

    jit_cmd("fetch", "origin", "refs/heads/*:refs/remotes/origin/*")
  end

  def test_exit_with_error = assert_status(1)

  def test_display_rejection
    assert_stderr <<~EOF
      From file://#{@remote.repo_path}
       ! [rejected] main -> origin/main (non-fast-forward)
    EOF
  end

  def test_do_not_update_local_ref
    refute_equal(@remote_head, @local_head)
    assert_equal(@local_head, commits(repo, ["origin/main"]).first)
  end
end

class Command::TestFetchMultipleBranchesInRemote < Command::TestFetch
  def setup
    super

    @remote = RemoteRepo.new("fetch-remote")
    @remote.jit_cmd("init", @remote.repo_path.to_s)

    %w[one dir/two three].each { write_commit(_1) }

    @remote.jit_cmd("branch", "topic", "@^")
    @remote.jit_cmd("checkout", "topic")
    write_commit("four")

    jit_cmd("remote", "add", "origin", "file://#{@remote.repo_path}")
    jit_cmd("config", "remote.origin.uploadpack", "#{jit_path} upload-pack")
  end

  def teardown
    super

    FileUtils.rm_rf(@remote.repo_path)
  end
end

class Command::TestFetchMultipleBranchesInRemoteBase < Command::TestFetchMultipleBranchesInRemote
  def test_display_new_branches_being_fetched
    jit_cmd("fetch")
    assert_status(0)

    assert_stderr <<~EOF
      From file://#{@remote.repo_path}
       * [new branch] main -> origin/main
       * [new branch] topic -> origin/topic
    EOF
  end

  def test_map_remote_refs
    jit_cmd("fetch")

    remote_main = @remote.repo.refs.read_ref("refs/heads/main")
    remote_topic = @remote.repo.refs.read_ref("refs/heads/topic")

    refute_equal(remote_main, remote_topic)
    assert_equal(remote_main, repo.refs.read_ref("refs/remotes/origin/main"))
    assert_equal(remote_topic, repo.refs.read_ref("refs/remotes/origin/topic"))
  end

  def test_map_remote_refs_to_different_local_ref
    jit_cmd("fetch", "origin", "refs/heads/*:refs/remotes/other/prefix-*")

    assert_equal(@remote.repo.refs.read_ref("refs/heads/main"),
      repo.refs.read_ref("refs/remotes/other/prefix-main"))

    assert_equal(@remote.repo.refs.read_ref("refs/heads/topic"),
      repo.refs.read_ref("refs/remotes/other/prefix-topic"))
  end

  def test_do_not_create_other_local_refs
    jit_cmd("fetch")

    assert_equal(["HEAD", "refs/remotes/origin/main", "refs/remotes/origin/topic"],
      repo.refs.list_all_refs.map(&:path).sort)
  end

  def test_retrieve_all_commits_from_remote_history
    jit_cmd("fetch")
    assert_object_count(13)

    remote_commits = commits(@remote.repo, [], all: true)
    assert_equal(4, remote_commits.size)

    assert_equal(remote_commits, commits(repo, [], all: true))
  end

  def test_retrieve_enough_information_to_checkout_remote_commits
    jit_cmd("fetch")

    jit_cmd("checkout", "origin/main")
    assert_workspace({
      "one.txt" => "one",
      "dir/two.txt" => "dir/two",
      "three.txt" => "three"
    })

    jit_cmd("checkout", "origin/topic")
    assert_workspace({
      "one.txt" => "one",
      "dir/two.txt" => "dir/two",
      "four.txt" => "four"
    })
  end
end

class Command::TestFetchMultipleBranchesInRemoteSpecificBranch < Command::TestFetchMultipleBranchesInRemote
  def setup
    super

    jit_cmd("fetch", "origin", "+refs/heads/*ic:refs/remotes/origin/*")
  end

  def test_display_branch_being_fetched
    assert_stderr <<~EOF
      From file://#{@remote.repo_path}
       * [new branch] topic -> origin/top
    EOF
  end

  def test_do_not_create_other_local_refs
    assert_equal(["HEAD", "refs/remotes/origin/top"],
      repo.refs.list_all_refs.map(&:path).sort)
  end

  def test_retrieve_only_commits_from_fetched_branch
    assert_object_count(10)

    remote_commits = commits(@remote.repo, ["topic"])
    assert_equal(3, remote_commits.size)

    assert_equal(remote_commits, commits(repo, [], all: true))
  end
end
