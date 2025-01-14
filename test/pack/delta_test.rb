require "minitest/autorun"
require "fileutils"
require "pathname"
require "securerandom"

require "database"
require "index"
require "pack"
require "pack/xdelta"

class Pack::TestDelta < Minitest::Test
  def setup
    super

    @blob_text_1 = SecureRandom.hex(256)
    @blob_text_2 = @blob_text_1 + "new content"
    @db_paths = Set.new
  end

  def teardown
    super

    @db_paths.each { FileUtils.rm_rf(it) }
  end

  def create_db(path)
    path = File.expand_path(path, __FILE__)
    FileUtils.mkdir_p(path)
    @db_paths.add(path)
    Database.new(Pathname.new(path))
  end

  def run_test(allow_ofs, processor)
    source = create_db("../db-source")
    target = create_db("../db-target")

    blobs = [@blob_text_1, @blob_text_2].map do |data|
      blob = Database::Blob.new(data)
      source.store(blob)
      Database::Entry.new(blob.oid, Index::REGULAR_MODE)
    end

    input, output = IO.pipe

    writer = Pack::Writer.new(output, source, allow_ofs: allow_ofs)
    writer.write_objects(blobs)

    stream = Pack::Stream.new(input)
    reader = Pack::Reader.new(stream)
    reader.read_header

    unpacker = processor.new(target, reader, stream, nil)
    unpacker.process_pack

    db = create_db("../db-target")

    full_blobs = blobs.map { db.load(it.oid) }

    assert_equal(@blob_text_1, full_blobs[0].data)
    assert_equal(@blob_text_2, full_blobs[1].data)

    infos = blobs.map { db.load_info(it.oid) }

    assert_equal(Database::Raw.new("blob", 512), infos[0])
    assert_equal(Database::Raw.new("blob", 523), infos[1])
  end

  def test_compress_blob
    index = Pack::XDelta.create_index(@blob_text_2)
    delta = index.compress(@blob_text_1).join("")

    assert_equal(2, delta.bytesize)
  end

  def test_unpack_objects_without_ofs_delta
    run_test(false, Pack::Unpacker)
  end

  def test_index_objects_without_ofs_delta
    run_test(false, Pack::Indexer)
  end

  def test_unpack_objects_with_ofs_delta
    run_test(true, Pack::Unpacker)
  end

  def test_index_objects_with_ofs_delta
    run_test(true, Pack::Indexer)
  end
end
