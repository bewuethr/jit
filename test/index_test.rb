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
    assert_equal(["alice.txt"], @index.each_entry.map(&:path))
  end

  def test_replace_file_with_directory
    @index.add("alice.txt", @oid, @stat)
    @index.add("bob.txt", @oid, @stat)
    @index.add("alice.txt/nested.txt", @oid, @stat)

    assert_equal(["alice.txt/nested.txt", "bob.txt"], @index.each_entry.map(&:path))
  end

  def test_replace_directory_with_file
    @index.add("alice.txt", @oid, @stat)
    @index.add("nested/bob.txt", @oid, @stat)

    @index.add("nested", @oid, @stat)

    assert_equal(["alice.txt", "nested"], @index.each_entry.map(&:path))
  end

  def test_recursively_replace_directory_with_file
    @index.add("alice.txt", @oid, @stat)
    @index.add("nested/bob.txt", @oid, @stat)
    @index.add("nested/inner/claire.txt", @oid, @stat)

    @index.add("nested", @oid, @stat)

    assert_equal(["alice.txt", "nested"], @index.each_entry.map(&:path))
  end
end
