require "minitest/autorun"

require "pathname"
require "securerandom"
require "index"

class TestIndex < Minitest::Test
  def setup
    @tmp_path = File.expand_path("../tmp", __FILE__)
    @index_path = Pathname.new(@tmp_path).join("index")
    @index = Index.new(@index_path)

    @stat = File.stat(__FILE__)
    @oid = SecureRandom.hex(20)
  end

  def test_add_single_file
    @index.add("alice.txt", @oid, @stat)
    assert_equal(["alice.txtx"], @index.each_entry.map(&:path))
  end
end
