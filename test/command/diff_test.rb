require "minitest/autorun"

require_relative "../command_helper"

class Command::TestDiff < Minitest::Test
  include CommandHelper

  def setup
    super
    write_file("1.txt", "one")

    jit_cmd("add", ".")
    commit("first commit")
  end

  def assert_diff(output)
    jit_cmd("diff")
    assert_stdout(output)
  end

  def test_report_unstaged_file_change
    write_file("1.txt", "changed")

    index_oid = short_index_oid_for("1.txt")
    workspace_oid = short_workspace_oid_for("1.txt")

    assert_diff <<~EOF
      diff --git a/1.txt b/1.txt
      index #{index_oid}..#{workspace_oid} 100644
      --- a/1.txt
      +++ b/1.txt
    EOF
  end

  def test_report_unstaged_mode_change
    make_executable("1.txt")

    assert_diff <<~EOF
      diff --git a/1.txt b/1.txt
      old mode 100644
      new mode 100755
    EOF
  end

  def test_report_unstaged_file_and_mode_change
    write_file("1.txt", "changed")
    make_executable("1.txt")

    index_oid = short_index_oid_for("1.txt")
    workspace_oid = short_workspace_oid_for("1.txt")

    assert_diff <<~EOF
      diff --git a/1.txt b/1.txt
      old mode 100644
      new mode 100755
      index #{index_oid}..#{workspace_oid}
      --- a/1.txt
      +++ b/1.txt
    EOF
  end

  def test_report_unstaged_deleted_file
    delete("1.txt")

    index_oid = short_index_oid_for("1.txt")

    assert_diff <<~EOF
      diff --git a/1.txt b/1.txt
      deleted file mode 100644
      index #{index_oid}..0000000
      --- a/1.txt
      +++ /dev/null
    EOF
  end
end

class Command::TestDiffHeadIndex < Command::TestDiff
  def assert_diff_cached(output)
    jit_cmd("diff", "--cached")
    assert_stdout(output)
  end

  def test_report_staged_file_change
    write_file("1.txt", "changed")
    jit_cmd("add", ".")

    head_oid = short_head_oid_for("1.txt")
    index_oid = short_index_oid_for("1.txt")

    assert_diff_cached <<~EOF
      diff --git a/1.txt b/1.txt
      index #{head_oid}..#{index_oid} 100644
      --- a/1.txt
      +++ b/1.txt
    EOF
  end

  def test_report_staged_mode_change
    make_executable("1.txt")
    jit_cmd("add", ".")

    assert_diff_cached <<~EOF
      diff --git a/1.txt b/1.txt
      old mode 100644
      new mode 100755
    EOF
  end

  def test_report_staged_file_and_mode_change
    write_file("1.txt", "changed")
    make_executable("1.txt")
    jit_cmd("add", ".")

    head_oid = short_head_oid_for("1.txt")
    index_oid = short_index_oid_for("1.txt")

    assert_diff_cached <<~EOF
      diff --git a/1.txt b/1.txt
      old mode 100644
      new mode 100755
      index #{head_oid}..#{index_oid}
      --- a/1.txt
      +++ b/1.txt
    EOF
  end

  def test_report_staged_deleted_file
    delete("1.txt")
    delete(".git/index")
    jit_cmd("add", ".")

    head_oid = short_head_oid_for("1.txt")

    assert_diff_cached <<~EOF
      diff --git a/1.txt b/1.txt
      deleted file mode 100644
      index #{head_oid}..0000000
      --- a/1.txt
      +++ /dev/null
    EOF
  end

  def test_report_staged_added_file
    write_file("new.txt", "new")
    jit_cmd("add", ".")

    index_oid = short_index_oid_for("new.txt")

    assert_diff_cached <<~EOF
      diff --git a/new.txt b/new.txt
      new file mode 100644
      index 0000000..#{index_oid}
      --- /dev/null
      +++ b/new.txt
    EOF
  end
end
