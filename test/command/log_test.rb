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
end
