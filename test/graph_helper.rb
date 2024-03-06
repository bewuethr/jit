require "fileutils"
require "pathname"

require "database"

module GraphHelper
  def setup = FileUtils.mkdir_p(db_path)

  def teardown = FileUtils.rm_rf(db_path)

  def db_path = Pathname.new(File.expand_path("../test-database", __FILE__))

  def database = @database ||= Database.new(db_path)

  def commit(parents, message)
    @commits ||= {}
    @time ||= Time.now

    parents = parents.map { |oid| @commits[oid] }
    author = Database::Author.new("A. U. Thor", "author@example.com", @time)
    commit = Database::Commit.new(parents, "0" * 40, author, message)

    database.store(commit)
    @commits[message] = commit.oid
  end

  def chain(names)
    names.each_cons(2) { |parent, message| commit([*parent], message) }
  end
end
