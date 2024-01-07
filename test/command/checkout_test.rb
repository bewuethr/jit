require "minitest/autorun"

require_relative "../command_helper"

class Command::TestCheckout < Minitest::Test
  include CommandHelper

  BASE_FILES = {
    "1.txt" => "1",
    "outer/2.txt" => "2",
    "outer/inner/3.txt" => "3"
  }

  def commit_all
    delete(".git/index")
    jit_cmd("add", ".")
    commit("change")
  end

  def commit_and_checkout(revision)
    commit_all
    jit_cmd("checkout", revision)
  end

  def assert_stale_file(filename)
    assert_stderr <<~EOF
      error: Your local changes to the following files would be overwritten by checkout:
      \t#{filename}
      Please commit your changes or stash them before you switch branches.
      Aborting
    EOF
  end

  def assert_stale_directory(filename)
    assert_stderr <<~EOF
      error: Updating the following directories would lose untracked files in them:
      \t#{filename}

      Aborting
    EOF
  end

  def assert_overwrite_conflict(filename)
    assert_stderr <<~EOF
      error: The following untracked working tree files would be overwritten by checkout:
      \t#{filename}
      Please move or remove them before you switch branches.
      Aborting
    EOF
  end

  def assert_remove_conflict(filename)
    assert_stderr <<~EOF
      error: The following untracked working tree files would be removed by checkout:
      \t#{filename}
      Please move or remove them before you switch branches.
      Aborting
    EOF
  end

  def assert_status(status)
    jit_cmd("status", "--porcelain")
    assert_stdout(status)
  end

  def setup
    super

    BASE_FILES.each do |name, contents|
      write_file(name, contents)
    end
    jit_cmd("add", ".")
    commit("first")
  end

  def test_update_changed_file
    write_file("1.txt", "changed")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_fail_to_update_modified_file
    write_file("1.txt", "changed")
    commit_all

    write_file("1.txt", "conflict")

    jit_cmd("checkout", "@^")
    assert_stale_file("1.txt")
  end

  def test_fail_to_update_modified_equal_file
    write_file("1.txt", "changed")
    commit_all

    write_file("1.txt", "1")

    jit_cmd("checkout", "@^")
    assert_stale_file("1.txt")
  end

  def test_fail_to_update_change_mode_file
    write_file("1.txt", "changed")
    commit_all

    make_executable("1.txt")

    jit_cmd("checkout", "@^")
    assert_stale_file("1.txt")
  end

  def test_restore_deleted_file
    write_file("1.txt", "changed")
    commit_all

    delete("1.txt")

    jit_cmd("checkout", "@^")
    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_restore_file_from_deleted_directory
    write_file("outer/inner/3.txt", "changed")
    commit_all

    delete("outer")
    jit_cmd("checkout", "@^")

    assert_workspace({
      "1.txt" => "1",
      "outer/inner/3.txt" => "3"
    })

    assert_status <<~EOF
      \ D outer/2.txt
    EOF
  end

  def test_fail_to_update_staged_file
    write_file("1.txt", "changed")
    commit_all

    write_file("1.txt", "conflict")
    jit_cmd("add", ".")

    jit_cmd("checkout", "@^")
    assert_stale_file("1.txt")
  end

  def test_update_staged_equal_file
    write_file("1.txt", "changed")
    commit_all

    write_file("1.txt", "1")
    jit_cmd("add", ".")
    jit_cmd("checkout", "@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_fail_to_update_staged_changed_mode_file
    write_file("1.txt", "changed")
    commit_all

    make_executable("1.txt")
    jit_cmd("add", ".")

    jit_cmd("checkout", "@^")
    assert_stale_file("1.txt")
  end

  def test_fail_to_update_unindexed_file
    write_file("1.txt", "changed")
    commit_all

    delete("1.txt")
    delete(".git/index")
    jit_cmd("add", ".")

    jit_cmd("checkout", "@^")
    assert_stale_file("1.txt")
  end

  def test_fail_to_update_unindexed_and_untracked_file
    write_file("1.txt", "changed")
    commit_all

    delete("1.txt")
    delete(".git/index")
    jit_cmd("add", ".")
    write_file("1.txt", "conflict")

    jit_cmd("checkout", "@^")
    assert_stale_file("1.txt")
  end

  def test_fail_to_update_unindexed_directory
    write_file("outer/inner/3.txt", "changed")
    commit_all

    delete("outer/inner")
    delete(".git/index")
    jit_cmd("add", ".")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/inner/3.txt")
  end

  def test_fail_to_update_with_file_at_parent_path
    write_file("outer/inner/3.txt", "changed")
    commit_all

    delete("outer/inner")
    write_file("outer/inner", "conflict")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/inner/3.txt")
  end

  def test_fail_to_update_with_staged_file_at_parent_path
    write_file("outer/inner/3.txt", "changed")
    commit_all

    delete("outer/inner")
    write_file("outer/inner", "conflict")
    jit_cmd("add", ".")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/inner/3.txt")
  end

  def test_fail_to_update_with_unstaged_file_at_parent_path
    write_file("outer/inner/3.txt", "changed")
    commit_all

    delete("outer/inner")
    delete(".git/index")
    jit_cmd("add", ".")
    write_file("outer/inner", "conflict")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/inner/3.txt")
  end

  def test_fail_to_update_with_file_at_child_path
    write_file("outer/2.txt", "changed")
    commit_all

    delete("outer/2.txt")
    write_file("outer/2.txt/extra.log", "conflict")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/2.txt")
  end

  def test_fail_to_update_with_staged_file_at_child_path
    write_file("outer/2.txt", "changed")
    commit_all

    delete("outer/2.txt")
    write_file("outer/2.txt/extra.log", "conflict")
    jit_cmd("add", ".")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/2.txt")
  end

  def test_remove_file
    write_file("94.txt", "94")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_remove_file_from_existing_directory
    write_file("outer/94.txt", "94")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_remove_file_from_new_directory
    write_file("new/94.txt", "94")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_noent("new")
    assert_status("")
    assert_status("")
  end

  def test_remove_file_from_new_nested_directory
    write_file("new/inner/94.txt", "94")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_noent("new")
    assert_status("")
  end

  def test_remove_file_from_non_empty_directory
    write_file("outer/94.txt", "94")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_fail_to_remove_modified_file
    write_file("outer/94.txt", "94")
    commit_all

    write_file("outer/94.txt", "conflict")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/94.txt")
  end

  def test_fail_to_remove_changed_mode_file
    write_file("outer/94.txt", "94")
    commit_all

    make_executable("outer/94.txt")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/94.txt")
  end

  def test_leave_deleted_file_deleted
    write_file("outer/94.txt", "94")
    commit_all

    delete("outer/94.txt")

    jit_cmd("checkout", "@^")
    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_leave_deleted_directory_deleted
    write_file("outer/94.txt", "94")
    commit_all

    delete("outer/inner")
    jit_cmd("checkout", "@^")

    assert_workspace({
      "1.txt" => "1",
      "outer/2.txt" => "2"
    })

    assert_status <<~EOF
      \ D outer/inner/3.txt
    EOF
  end

  def test_fail_to_remove_staged_file
    write_file("outer/94.txt", "94")
    commit_all

    write_file("outer/94.txt", "conflict")
    jit_cmd("add", ".")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/94.txt")
  end

  def test_fail_to_remove_staged_changed_mode_file
    write_file("outer/94.txt", "94")
    commit_all

    make_executable("outer/94.txt")
    jit_cmd("add", ".")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/94.txt")
  end

  def test_leave_unindexed_file_deleted
    write_file("outer/94.txt", "94")
    commit_all

    delete("outer/94.txt")
    delete(".git/index")
    jit_cmd("add", ".")
    jit_cmd("checkout", "@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_fail_to_remove_unindexed_untracked_file
    write_file("outer/94.txt", "94")
    commit_all

    delete("outer/94.txt")
    delete(".git/index")
    jit_cmd("add", ".")
    write_file("outer/94.txt", "conflict")

    jit_cmd("checkout", "@^")
    assert_remove_conflict("outer/94.txt")
  end

  def test_leave_unindexed_directory_deleted
    write_file("outer/inner/94.txt", "94")
    commit_all

    delete("outer/inner")
    delete(".git/index")
    jit_cmd("add", ".")
    jit_cmd("checkout", "@^")

    assert_workspace({
      "1.txt" => "1",
      "outer/2.txt" => "2"
    })

    assert_status <<~EOF
      D  outer/inner/3.txt
    EOF
  end

  def test_fail_to_remove_with_file_at_parent_path
    write_file("outer/inner/94.txt", "94")
    commit_all

    delete("outer/inner")
    write_file("outer/inner", "conflict")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/inner/94.txt")
  end

  def test_remove_file_with_staged_file_at_parent_path
    write_file("outer/inner/94.txt", "94")
    commit_all

    delete("outer/inner")
    write_file("outer/inner", "conflict")
    jit_cmd("add", ".")
    jit_cmd("checkout", "@^")

    assert_workspace({
      "1.txt" => "1",
      "outer/2.txt" => "2",
      "outer/inner" => "conflict"
    })

    assert_status <<~EOF
      A  outer/inner
      D  outer/inner/3.txt
    EOF
  end

  def test_fail_to_remove_with_unstaged_file_at_parent_path
    write_file("outer/inner/94.txt", "94")
    commit_all

    delete("outer/inner")
    delete(".git/index")
    jit_cmd("add", ".")
    write_file("outer/inner", "conflict")

    jit_cmd("checkout", "@^")

    assert_remove_conflict("outer/inner")
  end

  def test_fail_to_remove_with_file_at_child_path
    write_file("outer/94.txt", "94")
    commit_all

    delete("outer/94.txt")
    write_file("outer/94.txt/extra.log", "conflict")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/94.txt")
  end

  def test_remove_file_with_staged_file_at_child_path
    write_file("outer/94.txt", "94")
    commit_all

    delete("outer/94.txt")
    write_file("outer/94.txt/extra.log", "conflict")
    jit_cmd("add", ".")
    jit_cmd("checkout", "@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_add_file
    delete("1.txt")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_add_file_to_directory
    delete("outer/2.txt")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_add_directory
    delete("outer")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_fail_to_add_untracked_file
    delete("outer/2.txt")
    commit_all

    write_file("outer/2.txt", "conflict")

    jit_cmd("checkout", "@^")
    assert_overwrite_conflict("outer/2.txt")
  end

  def test_fail_to_add_added_file
    delete("outer/2.txt")
    commit_all

    write_file("outer/2.txt", "conflict")
    jit_cmd("add", ".")

    jit_cmd("checkout", "@^")
    assert_stale_file("outer/2.txt")
  end

  def test_add_staged_equal_file
    delete("outer/2.txt")
    commit_all

    write_file("outer/2.txt", "2")
    jit_cmd("add", ".")
    jit_cmd("checkout", "@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_fail_to_add_with_untracked_file_at_parent_path
    delete("outer/inner/3.txt")
    commit_all

    delete("outer/inner")
    write_file("outer/inner", "conflict")

    jit_cmd("checkout", "@^")
    assert_overwrite_conflict("outer/inner")
  end

  def test_add_file_with_added_file_at_parent_path
    delete("outer/inner/3.txt")
    commit_all

    delete("outer/inner")
    write_file("outer/inner", "conflict")
    jit_cmd("add", ".")
    jit_cmd("checkout", "@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_fail_to_add_with_untracked_file_at_child_path
    delete("outer/2.txt")
    commit_all

    write_file("outer/2.txt/extra.log", "conflict")

    jit_cmd("checkout", "@^")
    assert_stale_directory("outer/2.txt")
  end

  def test_add_file_with_added_file_at_child_path
    delete("outer/2.txt")
    commit_all

    write_file("outer/2.txt/extra.log", "conflict")
    jit_cmd("add", ".")
    jit_cmd("checkout", "@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_replace_file_with_directory
    delete("outer/inner")
    write_file("outer/inner", "in")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_replace_directory_with_file
    delete("outer/2.txt")
    write_file("outer/2.txt/nested.log", "nested")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_status("")
  end

  def test_maintains_workspace_modifications
    write_file("1.txt", "changed")
    commit_all

    write_file("outer/2.txt", "hello")
    delete("outer/inner")
    jit_cmd("checkout", "@^")

    assert_workspace({
      "1.txt" => "1",
      "outer/2.txt" => "hello"
    })

    assert_status <<~EOF
      \ M outer/2.txt
      \ D outer/inner/3.txt
    EOF
  end

  def test_maintains_index_modifications
    write_file("1.txt", "changed")
    commit_all

    write_file("outer/2.txt", "hello")
    write_file("outer/inner/4.txt", "world")
    jit_cmd("add", ".")
    jit_cmd("checkout", "@^")

    assert_workspace(BASE_FILES.merge({
      "outer/2.txt" => "hello",
      "outer/inner/4.txt" => "world"
    }))

    assert_status <<~EOF
      M  outer/2.txt
      A  outer/inner/4.txt
    EOF
  end
end

class Command::TestCheckoutChain < Minitest::Test
  include CommandHelper

  def setup
    super

    messages = ["first", "second", "third"]

    messages.each do |message|
      write_file("file.txt", message)
      jit_cmd("add", ".")
      commit(message)
    end

    jit_cmd("branch", "topic")
    jit_cmd("branch", "second", "@^")
  end

  def test_head_links_to_checked_out_branch
    jit_cmd("checkout", "topic")
    assert_equal("refs/heads/topic", repo.refs.current_ref.path)
  end

  def test_head_resolves_to_same_object_as_branch
    jit_cmd("checkout", "topic")
    assert_equal(repo.refs.read_ref("topic"), repo.refs.read_head)
  end

  def test_relative_rev_checkout_detaches_head
    jit_cmd("checkout", "topic^")
    assert_equal("HEAD", repo.refs.current_ref.path)
  end

  def test_relative_rev_checkout_puts_rev_value_in_head
    jit_cmd("checkout", "topic^")
    assert_equal(resolve_revision("topic^"), repo.refs.read_head)
  end
end
