require "minitest/autorun"

require_relative "../command_helper"

class Command::TestAdd < Minitest::Test
  include CommandHelper

  def assert_index(expected)
    repo.index.load
    actual = repo.index.each_entry.map { |entry| [entry.mode, entry.path] }
    assert_equal(expected, actual)
  end

  def test_add_regular_file
    write_file("hello.txt", "hello")

    jit_cmd("add", "hello.txt")

    assert_index([[0o100644, "hello.txt"]])
  end

  def test_add_executable_file
    write_file("hello.txt", "hello")
    make_executable("hello.txt")

    jit_cmd("add", "hello.txt")

    assert_index([[0o100755, "hello.txt"]])
  end

  def test_add_multiple_files
    write_file("hello.txt", "hello")
    write_file("world.txt", "world")

    jit_cmd("add", "hello.txt", "world.txt")

    assert_index([[0o100644, "hello.txt"], [0o100644, "world.txt"]])
  end

  def test_incrementally_add_files
    write_file("hello.txt", "hello")
    write_file("world.txt", "world")

    jit_cmd("add", "world.txt")

    assert_index([[0o100644, "world.txt"]])

    jit_cmd("add", "hello.txt")

    assert_index([[0o100644, "hello.txt"], [0o100644, "world.txt"]])
  end

  def test_add_directory
    write_file("a-dir/nested.txt", "content")

    jit_cmd("add", "a-dir")

    assert_index([[0o100644, "a-dir/nested.txt"]])
  end

  def test_add_repository_root
    write_file("a/b/c/file.txt", "content")

    jit_cmd("add", ".")

    assert_index([[0o100644, "a/b/c/file.txt"]])
  end

  def test_silent_success
    write_file("hello.txt", "hello")

    jit_cmd("add", "hello.txt")

    assert_status(0)
    assert_stdout("")
    assert_stderr("")
  end

  def test_fail_for_non_existent
    jit_cmd("add", "no-such-file")

    assert_stderr <<~EOF
      fatal: pathspec 'no-such-file' did not match any files
    EOF
    assert_status(128)
    assert_index([])
  end

  def test_fail_for_unreadable
    write_file("secret.txt", "")
    make_unreadable("secret.txt")

    jit_cmd("add", "secret.txt")

    assert_stderr <<~EOF
      error: open('secret.txt'): Permission denied
      fatal: adding files failed
    EOF
    assert_status(128)
    assert_index([])
  end

  def test_fail_if_locked
    write_file("file.txt", "")
    write_file(".git/index.lock", "")

    jit_cmd("add", "file.txt")

    assert_status(128)
    assert_index([])
  end
end
