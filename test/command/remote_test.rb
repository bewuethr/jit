require "minitest/autorun"

require_relative "../command_helper"

require "rev_list"

class Command::TestRemote < Minitest::Test
  include CommandHelper
end

class Command::TestRemoteAdd < Command::TestRemote
  def setup
    super

    jit_cmd(*%w[remote add origin ssh://example.com/repo])
  end

  def test_fail_to_add_existing_remote
    jit_cmd("remote", "add", "origin", "url")
    assert_status(128)
    assert_stderr("fatal: remote origin already exists.\n")
  end

  def test_list_remote
    jit_cmd("remote")

    assert_stdout <<~EOF
      origin
    EOF
  end

  def test_list_remote_with_urls
    jit_cmd("remote", "--verbose")

    assert_stdout <<~EOF
      origin\tssh://example.com/repo (fetch)
      origin\tssh://example.com/repo (push)
    EOF
  end

  def test_set_catch_all_refspec
    jit_cmd("config", "--local", "--get-all", "remote.origin.fetch")

    assert_stdout <<~EOF
      +refs/heads/*:refs/remotes/origin/*
    EOF
  end
end

class Command::TestRemoteAddWithTrackingBranches < Command::TestRemote
  def setup
    super

    jit_cmd(*%w[remote add origin ssh://example.com/repo -t main -t topic])
  end

  def test_set_fetch_refspec_for_each_branch
    jit_cmd("config", "--local", "--get-all", "remote.origin.fetch")

    assert_stdout <<~EOF
      +refs/heads/main:refs/remotes/origin/main
      +refs/heads/topic:refs/remotes/origin/topic
    EOF
  end
end

class Command::TestRemoteRemoveRemote < Command::TestRemote
  def setup
    super

    jit_cmd(*%w[remote add origin ssh://example.com/repo])
  end

  def test_remove_remote
    jit_cmd("remote", "remove", "origin")
    assert_status(0)

    jit_cmd("remote")
    assert_stdout("")
  end

  def test_fail_to_remove_missing_remote
    jit_cmd("remote", "remove", "no-such")
    assert_status(128)
    assert_stderr("fatal: No such remote: no-such\n")
  end
end
