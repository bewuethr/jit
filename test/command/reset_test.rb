require "minitest/autorun"

require_relative "../command_helper"

class Command::TestReset < Minitest::Test
  include CommandHelper

  def assert_index(contents)
    files = {}
    repo.index.load

    repo.index.each_entry do |entry|
      files[entry.path] = repo.database.load(entry.oid).data
    end

    assert_equal(contents, files)
  end
end

class Command::TestResetNoHeadCommit < Command::TestReset
  def setup
    super

    write_file("a.txt", "1")
    write_file("outer/b.txt", "2")
    write_file("outer/inner/c.txt", "3")

    jit_cmd("add", ".")
  end

  def assert_unchanged_workspace
    assert_workspace({
      "a.txt" => "1",
      "outer/b.txt" => "2",
      "outer/inner/c.txt" => "3"
    })
  end

  def test_remove_evertything_from_index
    jit_cmd("reset")

    assert_index({})
    assert_unchanged_workspace
  end

  def test_remove_single_file_from_index
    jit_cmd("reset", "a.txt")

    assert_index({
      "outer/b.txt" => "2",
      "outer/inner/c.txt" => "3"
    })

    assert_unchanged_workspace
  end

  def test_remove_directory_from_index
    jit_cmd("reset", "outer")

    assert_index({"a.txt" => "1"})

    assert_unchanged_workspace
  end
end

class Command::TestResetWithHeadCommit < Command::TestReset
  def setup
    super

    write_file("a.txt", "1")
    write_file("outer/b.txt", "2")
    write_file("outer/inner/c.txt", "3")

    jit_cmd("add", ".")
    commit("first")

    write_file("outer/b.txt", "4")
    jit_cmd("add", ".")
    commit("second")

    jit_cmd("rm", "a.txt")
    write_file("outer/d.txt", "5")
    write_file("outer/inner/c.txt", "6")
    jit_cmd("add", ".")
    write_file("outer/e.txt", "7")

    @head_oid = repo.refs.read_head
  end

  def assert_unchanged_head
    assert_equal(@head_oid, repo.refs.read_head)
  end

  def assert_unchanged_workspace
    assert_workspace({
      "outer/b.txt" => "4",
      "outer/d.txt" => "5",
      "outer/e.txt" => "7",
      "outer/inner/c.txt" => "6"
    })
  end

  def test_restore_file_removed_from_index
    jit_cmd("reset", "a.txt")

    assert_index({
      "a.txt" => "1",
      "outer/b.txt" => "4",
      "outer/d.txt" => "5",
      "outer/inner/c.txt" => "6"
    })

    assert_unchanged_head
    assert_unchanged_workspace
  end

  def test_reset_file_modified_in_index
    jit_cmd("reset", "outer/inner")

    assert_index({
      "outer/b.txt" => "4",
      "outer/d.txt" => "5",
      "outer/inner/c.txt" => "3"
    })

    assert_unchanged_head
    assert_unchanged_workspace
  end

  def test_remove_file_added_to_index
    jit_cmd("reset", "outer/d.txt")

    assert_index({
      "outer/b.txt" => "4",
      "outer/inner/c.txt" => "6"
    })

    assert_unchanged_head
    assert_unchanged_workspace
  end

  def test_reset_file_to_specific_commit
    jit_cmd("reset", "@^", "outer/b.txt")

    assert_index({
      "outer/b.txt" => "2",
      "outer/d.txt" => "5",
      "outer/inner/c.txt" => "6"
    })

    assert_unchanged_head
    assert_unchanged_workspace
  end

  def test_reset_whole_index
    jit_cmd("reset")

    assert_index({
      "a.txt" => "1",
      "outer/b.txt" => "4",
      "outer/inner/c.txt" => "3"
    })

    assert_unchanged_head
    assert_unchanged_workspace
  end

  def test_reset_whole_index_and_move_head
    jit_cmd("reset", "@^")

    assert_index({
      "a.txt" => "1",
      "outer/b.txt" => "2",
      "outer/inner/c.txt" => "3"
    })

    assert_equal(repo.database.load(@head_oid).parent, repo.refs.read_head)

    assert_unchanged_workspace
  end

  def test_move_head_and_leave_index_unchanged
    jit_cmd("reset", "--soft", "@^")

    assert_index({
      "outer/b.txt" => "4",
      "outer/d.txt" => "5",
      "outer/inner/c.txt" => "6"
    })

    assert_equal(repo.database.load(@head_oid).parent, repo.refs.read_head)

    assert_unchanged_workspace
  end
end
