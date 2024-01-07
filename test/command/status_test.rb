require "minitest/autorun"

require_relative "../command_helper"

class Command::TestStatus < Minitest::Test
  include CommandHelper

  def assert_status(output)
    jit_cmd("status", "--porcelain")
    assert_stdout(output)
  end

  def test_list_untracked_files
    write_file("file.txt", "")
    write_file("another.txt", "")

    assert_status <<~EOF
      ?? another.txt
      ?? file.txt
    EOF
  end

  def test_list_untracked_files_not_in_index
    write_file("committed.txt", "")
    jit_cmd("add", ".")
    commit "commit message"

    write_file("file.txt", "")

    assert_status <<~EOF
      ?? file.txt
    EOF
  end

  def test_list_untracked_directories_without_contents
    write_file("file.txt", "")
    write_file("dir/another.txt", "")

    assert_status <<~EOF
      ?? dir/
      ?? file.txt
    EOF
  end

  def test_list_untracked_files_in_tracked_directories
    write_file("a/b/inner.txt", "")
    jit_cmd("add", ".")
    commit "commit message"

    write_file("a/outer.txt", "")
    write_file("a/b/c/file.txt", "")

    assert_status <<~EOF
      ?? a/b/c/
      ?? a/outer.txt
    EOF
  end

  def test_not_list_empty_untracked_directories
    mkdir("outer")

    assert_status("")
  end

  def test_list_untracked_unempty_directories
    write_file("outer/inner/file.txt", "")

    assert_status <<~EOF
      ?? outer/
    EOF
  end
end

class Command::TestStatusIndexWorkspace < Minitest::Test
  include CommandHelper

  def setup
    super
    write_file("1.txt", "one")
    write_file("a/2.txt", "two")
    write_file("a/b/3.txt", "three")

    jit_cmd("add", ".")
    commit("commit message")
  end

  def assert_status(output)
    jit_cmd("status", "--porcelain")
    assert_stdout(output)
  end

  def test_print_nothing_when_no_changes
    assert_status("")
  end

  def test_report_files_with_modified_contents
    write_file("1.txt", "changed")
    write_file("a/2.txt", "modified")

    assert_status <<~EOF
      \ M 1.txt
      \ M a/2.txt
    EOF
  end

  def test_report_files_with_changed_mode
    make_executable("a/2.txt")

    assert_status <<~EOF
      \ M a/2.txt
    EOF
  end

  def test_report_changed_file_with_same_size
    sleep 0.001
    write_file("a/b/3.txt", "hello")

    assert_status <<~EOF
      \ M a/b/3.txt
    EOF
  end

  def test_print_nothing_if_file_is_touched
    touch("1.txt")

    assert_status("")
  end

  def test_report_deleted_file
    delete("a/2.txt")

    assert_status <<~EOF
      \ D a/2.txt
    EOF
  end

  def test_report_files_in_deleted_directories
    delete("a")

    assert_status <<~EOF
      \ D a/2.txt
      \ D a/b/3.txt
    EOF
  end
end

class Command::TestStatusHeadIndex < Minitest::Test
  include CommandHelper

  def setup
    super
    write_file("1.txt", "one")
    write_file("a/2.txt", "two")
    write_file("a/b/3.txt", "three")

    jit_cmd("add", ".")
    commit("first commit")
  end

  def assert_status(output)
    jit_cmd("status", "--porcelain")
    assert_stdout(output)
  end

  def assert_long_status(output)
    jit_cmd("status")
    assert_stdout(output)
  end

  def test_report_file_added_to_tracked_directory
    write_file("a/4.txt", "four")
    jit_cmd("add", ".")

    assert_status <<~EOF
      A  a/4.txt
    EOF
  end

  def test_report_file_added_to_untracked_directory
    write_file("d/e/5.txt", "five")
    jit_cmd("add", ".")

    assert_status <<~EOF
      A  d/e/5.txt
    EOF
  end

  def test_report_modified_modes
    make_executable("1.txt")
    jit_cmd("add", ".")

    assert_status <<~EOF
      M  1.txt
    EOF
  end

  def test_report_modified_contents
    write_file("a/b/3.txt", "changed")
    jit_cmd("add", ".")

    assert_status <<~EOF
      M  a/b/3.txt
    EOF
  end

  def test_report_deleted_files
    delete("1.txt")
    delete(".git/index")
    jit_cmd("add", ".")

    assert_status <<~EOF
      D  1.txt
    EOF
  end

  def test_report_all_files_in_deleted_directory
    delete("a")
    delete(".git/index")
    jit_cmd("add", ".")

    assert_status <<~EOF
      D  a/2.txt
      D  a/b/3.txt
    EOF
  end

  def test_report_files_ordered_for_long_format
    delete("a/2.txt")
    delete(".git/index")
    write_file("1.txt", "changed")
    write_file("z.txt", "new")
    jit_cmd("add", ".")

    assert_long_status <<~EOF
      On branch main
      Changes to be committed:

      \tmodified:   1.txt
      \tdeleted:    a/2.txt
      \tnew file:   z.txt

    EOF
  end
end
