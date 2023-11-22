require "minitest/autorun"

require_relative "../command_helper"

class Command::TestCheckout < Minitest::Test
  include CommandHelper

  def commit_all
    delete(".git/index")
    jit_cmd("add", ".")
    commit("change")
  end

  def commit_and_checkout(revision)
    commit_all
    jit_cmd("checkout", revision)
  end

  BASE_FILES = {
    "1.txt" => "1",
    "outer/2.txt" => "2",
    "outer/inner/3.txt" => "3"
  }

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
  end

  def test_remove_file
    write_file("94.txt", "94")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
  end

  def test_remove_file_from_existing_directory
    write_file("outer/94.txt", "94")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
  end

  def test_remove_file_from_new_directory
    write_file("new/94.txt", "94")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_noent("new")
  end

  def test_remove_file_from_new_nested_directory
    write_file("new/inner/94.txt", "94")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
    assert_noent("new")
  end

  def test_remove_file_from_non_empty_directory
    write_file("outer/94.txt", "94")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
  end

  def test_add_file
    delete("1.txt")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
  end

  def test_add_file_to_directory
    delete("outer/2.txt")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
  end

  def test_add_directory
    delete("outer")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
  end

  def test_replace_file_with_directory
    delete("outer/inner")
    write_file("outer/inner", "in")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
  end

  def test_replace_directory_with_file
    delete("outer/2.txt")
    write_file("outer/2.txt/nested.log", "nested")
    commit_and_checkout("@^")

    assert_workspace(BASE_FILES)
  end
end
