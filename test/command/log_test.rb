require "minitest/autorun"

require_relative "../command_helper"

class Command::TestLog < Minitest::Test
  include CommandHelper

  def commit_file(message)
    write_file("file.txt", message)
    jit_cmd("add", ".")
    commit(message)
  end

  def setup
    super

    ["A", "B", "C"].each do |message|
      commit_file(message)
    end

    jit_cmd("branch", "topic", "@^^")

    @commits = ["@", "@^", "@~2"].map { |rev| load_commit(rev) }
  end

  def test_print_log_in_medium_format
    jit_cmd("log")

    assert_stdout <<~EOF
      commit #{@commits[0].oid}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[0].author.readable_time}

          C

      commit #{@commits[1].oid}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[1].author.readable_time}

          B

      commit #{@commits[2].oid}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[2].author.readable_time}

          A
    EOF
  end

  def test_print_medium_format_with_short_commit_ids
    jit_cmd("log", "--abbrev-commit")

    assert_stdout <<~EOF
      commit #{repo.database.short_oid(@commits[0].oid)}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[0].author.readable_time}

          C

      commit #{repo.database.short_oid(@commits[1].oid)}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[1].author.readable_time}

          B

      commit #{repo.database.short_oid(@commits[2].oid)}
      Author: A. U. Thor <author@example.com>
      Date:   #{@commits[2].author.readable_time}

          A
    EOF
  end

  def test_print_oneline_format
    jit_cmd("log", "--oneline")

    assert_stdout <<~EOF
      #{repo.database.short_oid(@commits[0].oid)} C
      #{repo.database.short_oid(@commits[1].oid)} B
      #{repo.database.short_oid(@commits[2].oid)} A
    EOF
  end

  def test_print_oneline_format_without_short_commit_ids
    jit_cmd("log", "--pretty=oneline")

    assert_stdout <<~EOF
      #{@commits[0].oid} C
      #{@commits[1].oid} B
      #{@commits[2].oid} A
    EOF
  end

  def test_print_with_short_decorations
    jit_cmd("log", "--pretty=oneline", "--decorate=short")

    assert_stdout <<~EOF
      #{@commits[0].oid} (HEAD -> main) C
      #{@commits[1].oid} B
      #{@commits[2].oid} (topic) A
    EOF
  end

  def test_print_with_detached_head
    jit_cmd("checkout", "@")
    jit_cmd("log", "--pretty=oneline", "--decorate=short")

    assert_stdout <<~EOF
      #{@commits[0].oid} (HEAD, main) C
      #{@commits[1].oid} B
      #{@commits[2].oid} (topic) A
    EOF
  end

  def test_print_with_full_decorations
    jit_cmd("log", "--pretty=oneline", "--decorate=full")

    assert_stdout <<~EOF
      #{@commits[0].oid} (HEAD -> refs/heads/main) C
      #{@commits[1].oid} B
      #{@commits[2].oid} (refs/heads/topic) A
    EOF
  end
end
