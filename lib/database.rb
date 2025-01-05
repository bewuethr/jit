require "digest/sha1"
require "forwardable"
require "pathname"
require "strscan"

require_relative "database/author"
require_relative "database/blob"
require_relative "database/commit"
require_relative "database/entry"
require_relative "database/loose"
require_relative "database/tree"
require_relative "database/tree_diff"
require_relative "path_filter"

class Database
  TYPES = {
    "blob" => Blob,
    "tree" => Tree,
    "commit" => Commit
  }

  Raw = Struct.new(:type, :size, :data)

  extend Forwardable
  def_delegators :@backend, :has?, :load_info, :load_raw, :prefix_match

  def initialize(pathname)
    @pathname = pathname
    @objects = {}
    @backend = Loose.new(pathname)
  end

  def store(object)
    content = serialize_object(object)
    object.oid = hash_content(content)

    @backend.write_object(object.oid, content)
  end

  def hash_object(object) = hash_content(serialize_object(object))

  def short_oid(oid) = oid[0..6]

  def tree_entry(oid) = Entry.new(oid, Tree::TREE_MODE)

  def load(oid) = @objects[oid] ||= read_object(oid)

  def tree_diff(a, b, filter = PathFilter.new)
    diff = TreeDiff.new(self)
    diff.compare_oids(a, b, filter)
    diff.changes
  end

  def load_tree_entry(oid, pathname)
    commit = load(oid)
    root = Database::Entry.new(commit.tree, Tree::TREE_MODE)

    return root unless pathname

    pathname.each_filename.reduce(root) do |entry, name|
      entry ? load(entry.oid).entries[name] : nil
    end
  end

  def load_tree_list(oid, pathname = nil)
    return {} unless oid

    entry = load_tree_entry(oid, pathname)
    list = {}

    build_list(list, entry, pathname || Pathname.new(""))
    list
  end

  def pack_path = @pathname.join("pack")

  private def serialize_object(object)
    string = object.to_s.b
    "#{object.type} #{string.bytesize}\0#{string}"
  end

  private def hash_content(string) = Digest::SHA1.hexdigest(string)

  private def object_path(oid) = @pathname.join(oid[0..1], oid[2..])

  private def read_object(oid)
    raw = load_raw(oid)
    scanner = StringScanner.new(raw.data)

    object = TYPES[raw.type].parse(scanner)
    object.oid = oid

    object
  end

  private def read_object_header(oid, read_bytes = nil)
    path = object_path(oid)
    data = Zlib::Inflate.new.inflate(File.read(path, read_bytes))
    scanner = StringScanner.new(data)

    type = scanner.scan_until(/ /).strip
    size = scanner.scan_until(/\0/)[0..-2].to_i

    [type, size, scanner]
  end

  private def build_list(list, entry, prefix)
    return unless entry
    return list[prefix.to_s] = entry unless entry.tree?

    load(entry.oid).entries.each do |name, item|
      build_list(list, item, prefix.join(name))
    end
  end
end
