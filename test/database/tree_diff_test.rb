require "minitest/autorun"
require "fileutils"
require "pathname"

require "database"

FakeEntry = Struct.new(:path, :oid, :mode) do
  def parent_directories = Pathname.new(path).descend.to_a[0..-2]

  def basename = Pathname.new(path).basename
end

class Database::TestTreeDiff < Minitest::Test
  def setup = FileUtils.mkdir_p(db_path)

  def teardown = FileUtils.rm_rf(db_path)

  def db_path = Pathname.new(File.expand_path("../../test-objects", __FILE__))

  def store_tree(contents)
    database = Database.new(db_path)

    entries = contents.map do |path, data|
      blob = Database::Blob.new(data)
      database.store(blob)

      FakeEntry.new(path, blob.oid, 0o100644)
    end

    tree = Database::Tree.build(entries)
    tree.traverse { |t| database.store(t) }

    tree.oid
  end

  def tree_diff(a, b) = Database.new(db_path).tree_diff(a, b)

  def test_report_changed_file
    tree_a = store_tree({
      "alice.txt" => "alice",
      "bob.txt" => "bob"
    })

    tree_b = store_tree({
      "alice.txt" => "changed",
      "bob.txt" => "bob"
    })

    assert_equal(tree_diff(tree_a, tree_b),
      Pathname.new("alice.txt") => [
        Database::Entry.new("ca56b59dbf8c0884b1b9ceb306873b24b73de969", 0o100644),
        Database::Entry.new("21fb1eca31e64cd3914025058b21992ab76edcf9", 0o100644)
      ])
  end

  def test_report_added_file
    tree_a = store_tree({
      "alice.txt" => "alice"
    })

    tree_b = store_tree({
      "alice.txt" => "alice",
      "bob.txt" => "bob"
    })

    assert_equal(tree_diff(tree_a, tree_b),
      Pathname.new("bob.txt") => [
        nil,
        Database::Entry.new("2529de8969e5ee206e572ed72a0389c3115ad95c", 0o100644)
      ])
  end

  def test_report_deleted_file
    tree_a = store_tree({
      "alice.txt" => "alice",
      "bob.txt" => "bob"
    })

    tree_b = store_tree({
      "alice.txt" => "alice"
    })

    assert_equal(tree_diff(tree_a, tree_b),
      Pathname.new("bob.txt") => [
        Database::Entry.new("2529de8969e5ee206e572ed72a0389c3115ad95c", 0o100644),
        nil
      ])
  end

  def test_report_added_file_in_directory
    tree_a = store_tree({
      "1.txt" => "1",
      "outer/2.txt" => "2"
    })

    tree_b = store_tree({
      "1.txt" => "1",
      "outer/2.txt" => "2",
      "outer/new/4.txt" => "4"
    })

    assert_equal(tree_diff(tree_a, tree_b),
      Pathname.new("outer/new/4.txt") => [
        nil,
        Database::Entry.new("bf0d87ab1b2b0ec1a11a3973d2845b42413d9767", 0o100644)
      ])
  end

  def test_report_deleted_file_in_directory
    tree_a = store_tree({
      "1.txt" => "1",
      "outer/2.txt" => "2",
      "outer/inner/3.txt" => "3"
    })

    tree_b = store_tree({
      "1.txt" => "1",
      "outer/2.txt" => "2"
    })

    assert_equal(tree_diff(tree_a, tree_b),
      Pathname.new("outer/inner/3.txt") => [
        Database::Entry.new("e440e5c842586965a7fb77deda2eca68612b1f53", 0o100644),
        nil
      ])
  end
end
