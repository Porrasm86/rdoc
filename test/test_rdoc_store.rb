require File.expand_path '../xref_test_case', __FILE__

class TestRDocStore < XrefTestCase

  OBJECT_ANCESTORS = defined?(::BasicObject) ? %w[BasicObject] : []

  def setup
    super

    @tmpdir = File.join Dir.tmpdir, "test_rdoc_ri_store_#{$$}"
    @s = RDoc::RI::Store.new @tmpdir

    @top_level = @store.add_file 'file.rb'

    @klass = @top_level.add_class RDoc::NormalClass, 'Object'
    @klass.add_comment 'original', @top_level

    @cmeth = RDoc::AnyMethod.new nil, 'cmethod'
    @cmeth.singleton = true
    @cmeth.record_location @top_level

    @meth = RDoc::AnyMethod.new nil, 'method'
    @meth.record_location @top_level

    @meth_bang = RDoc::AnyMethod.new nil, 'method!'
    @meth_bang.record_location @top_level

    @attr = RDoc::Attr.new nil, 'attr', 'RW', ''
    @attr.record_location @top_level

    @klass.add_method @cmeth
    @klass.add_method @meth
    @klass.add_method @meth_bang
    @klass.add_attribute @attr

    @nest_klass = @klass.add_class RDoc::NormalClass, 'SubClass'
    @nest_meth = RDoc::AnyMethod.new nil, 'method'
    @nest_meth.record_location @top_level

    @nest_incl = RDoc::Include.new 'Incl', ''
    @nest_incl.record_location @top_level

    @nest_klass.add_method @nest_meth
    @nest_klass.add_include @nest_incl
  end

  def teardown
    super

    FileUtils.rm_rf @tmpdir
  end

  def mu_pp obj
    s = ''
    s = PP.pp obj, s
    s.force_encoding Encoding.default_external if defined? Encoding
    s.chomp
  end

  def assert_cache imethods, cmethods, attrs, modules, ancestors = {}
    imethods ||= { 'Object' => %w[method method!] }
    cmethods ||= { 'Object' => %w[cmethod] }
    attrs    ||= { 'Object' => ['attr_accessor attr'] }

    # this is sort-of a hack
    @s.clean_cache_collection ancestors

    expected = {
      :ancestors        => ancestors,
      :attributes       => attrs,
      :class_methods    => cmethods,
      :encoding         => nil,
      :instance_methods => imethods,
      :modules          => modules,
    }

    @s.save_cache

    assert_equal expected, @s.cache
  end

  def assert_directory path
    assert File.directory?(path), "#{path} is not a directory"
  end

  def assert_file path
    assert File.file?(path), "#{path} is not a file"
  end

  def refute_file path
    refute File.exist?(path), "#{path} exists"
  end

  def test_add_file
    top_level = @store.add_file 'file.rb'

    assert_kind_of RDoc::TopLevel, top_level
    assert_equal @store, top_level.store
    assert_equal 'file.rb', top_level.name
    assert_includes @store.all_files, top_level

    assert_same top_level, @store.add_file('file.rb')
    refute_same top_level, @store.add_file('other.rb')
  end

  def test_all_classes_and_modules
    expected = %w[
      C1 C2 C2::C3 C2::C3::H1 C3 C3::H1 C3::H2 C4 C4::C4 C5 C5::C1
      Child
      M1 M1::M2
      Object
      Object::SubClass
      Parent
    ]

    assert_equal expected,
                 @store.all_classes_and_modules.map { |m| m.full_name }.sort
  end

  def test_all_files
    assert_equal %w[file.rb xref_data.rb],
                 @store.all_files.map { |m| m.full_name }.sort
  end

  def test_attributes
    @s.cache[:attributes]['Object'] = %w[attr]

    expected = { 'Object' => %w[attr] }

    assert_equal expected, @s.attributes
  end

  def test_class_file
    assert_equal File.join(@tmpdir, 'Object', 'cdesc-Object.ri'),
                 @s.class_file('Object')
    assert_equal File.join(@tmpdir, 'Object', 'SubClass', 'cdesc-SubClass.ri'),
                 @s.class_file('Object::SubClass')
  end

  def test_class_methods
    @s.cache[:class_methods]['Object'] = %w[method]

    expected = { 'Object' => %w[method] }

    assert_equal expected, @s.class_methods
  end

  def test_class_path
    assert_equal File.join(@tmpdir, 'Object'), @s.class_path('Object')
    assert_equal File.join(@tmpdir, 'Object', 'SubClass'),
                 @s.class_path('Object::SubClass')
  end

  def test_classes
    expected = %w[
      C1 C2 C2::C3 C2::C3::H1 C3 C3::H1 C3::H2 C4 C4::C4 C5 C5::C1
      Child
      Object
      Object::SubClass
      Parent
    ]

    assert_equal expected, @store.all_classes.map { |m| m.full_name }.sort
  end

  def test_complete
    @c2.add_module_alias @c2_c3, 'A1', @top_level

    @store.complete :public

    a1 = @xref_data.find_class_or_module 'C2::A1'

    assert_equal 'C2::A1', a1.full_name
    refute_empty a1.aliases
  end

  def test_find_class_named
    assert_equal @c1, @store.find_class_named('C1')

    assert_equal @c2_c3, @store.find_class_named('C2::C3')
  end

  def test_find_class_named_from
    assert_equal @c5_c1, @store.find_class_named_from('C1', 'C5')

    assert_equal @c1,    @store.find_class_named_from('C1', 'C4')
  end

  def test_find_class_or_module
    assert_equal @m1, @store.find_class_or_module('M1')
    assert_equal @c1, @store.find_class_or_module('C1')

    assert_equal @m1, @store.find_class_or_module('::M1')
    assert_equal @c1, @store.find_class_or_module('::C1')
  end

  def test_find_file_named
    assert_equal @xref_data, @store.find_file_named(@file_name)
  end

  def test_find_module_named
    assert_equal @m1,    @store.find_module_named('M1')
    assert_equal @m1_m2, @store.find_module_named('M1::M2')
  end

  def test_friendly_path
    @s.path = @tmpdir
    @s.type = nil
    assert_equal @s.path, @s.friendly_path

    @s.type = :extra
    assert_equal @s.path, @s.friendly_path

    @s.type = :system
    assert_equal "ruby core", @s.friendly_path

    @s.type = :site
    assert_equal "ruby site", @s.friendly_path

    @s.type = :home
    assert_equal "~/.ri", @s.friendly_path

    @s.type = :gem
    @s.path = "#{@tmpdir}/gem_repository/doc/gem_name-1.0/ri"
    assert_equal "gem gem_name-1.0", @s.friendly_path
  end

  def test_dry_run
    refute @s.dry_run

    @s.dry_run = true

    assert @s.dry_run
  end

  def test_instance_methods
    @s.cache[:instance_methods]['Object'] = %w[method]

    expected = { 'Object' => %w[method] }

    assert_equal expected, @s.instance_methods
  end

  def test_load_cache
    cache = {
      :encoding => :encoding_value,
      :methods  => %w[Object#method],
      :modules  => %w[Object],
    }

    Dir.mkdir @tmpdir

    open File.join(@tmpdir, 'cache.ri'), 'wb' do |io|
      Marshal.dump cache, io
    end

    @s.load_cache

    assert_equal cache, @s.cache

    assert_equal :encoding_value, @s.encoding
  end

  def test_load_cache_encoding_differs
    skip "Encoding not implemented" unless Object.const_defined? :Encoding

    cache = {
      :encoding => Encoding::ISO_8859_1,
      :methods  => %w[Object#method],
      :modules  => %w[Object],
    }

    Dir.mkdir @tmpdir

    open File.join(@tmpdir, 'cache.ri'), 'wb' do |io|
      Marshal.dump cache, io
    end

    @s.encoding = Encoding::UTF_8

    @s.load_cache

    assert_equal cache, @s.cache

    assert_equal Encoding::UTF_8, @s.encoding
  end

  def test_load_cache_no_cache
    cache = {
      :ancestors        => {},
      :attributes       => {},
      :class_methods    => {},
      :encoding         => nil,
      :instance_methods => {},
      :modules          => [],
    }

    @s.load_cache

    assert_equal cache, @s.cache
  end

  def test_load_class
    @s.save_class @klass

    assert_equal @klass, @s.load_class('Object')
  end

  def test_load_method_bang
    @s.save_method @klass, @meth_bang

    meth = @s.load_method('Object', '#method!')
    assert_equal @meth_bang, meth
    assert_equal @s, meth.store
  end

  def test_method_file
    assert_equal File.join(@tmpdir, 'Object', 'method-i.ri'),
                 @s.method_file('Object', 'Object#method')

    assert_equal File.join(@tmpdir, 'Object', 'method%21-i.ri'),
                 @s.method_file('Object', 'Object#method!')

    assert_equal File.join(@tmpdir, 'Object', 'SubClass', 'method%21-i.ri'),
                 @s.method_file('Object::SubClass', 'Object::SubClass#method!')

    assert_equal File.join(@tmpdir, 'Object', 'method-c.ri'),
                 @s.method_file('Object', 'Object::method')
  end

  def test_modules
    assert_equal %w[M1 M1::M2],
                 @store.all_modules.map { |m| m.full_name }.sort
  end

  def test_page
    page = @store.add_file 'PAGE.txt'
    page.parser = RDoc::Parser::Simple

    assert_nil @store.page 'no such page'

    assert_equal page, @store.page('PAGE')
  end

  def test_save_cache
    @s.save_class @klass
    @s.save_method @klass, @meth
    @s.save_method @klass, @cmeth
    @s.save_class @nest_klass
    @s.encoding = :encoding_value

    @s.save_cache

    assert_file File.join(@tmpdir, 'cache.ri')

    expected = {
      :ancestors => {
        'Object::SubClass' => %w[Incl Object],
      },
      :attributes => { 'Object' => ['attr_accessor attr'] },
      :class_methods => { 'Object' => %w[cmethod] },
      :instance_methods => {
        'Object' => %w[method method!],
        'Object::SubClass' => %w[method],
      },
      :modules => %w[Object Object::SubClass],
      :encoding => :encoding_value,
    }

    expected[:ancestors]['Object'] = %w[BasicObject] if defined?(::BasicObject)

    open File.join(@tmpdir, 'cache.ri'), 'rb' do |io|
      cache = Marshal.load io.read

      assert_equal expected, cache
    end
  end

  def test_save_cache_dry_run
    @s.dry_run = true

    @s.save_class @klass
    @s.save_method @klass, @meth
    @s.save_method @klass, @cmeth
    @s.save_class @nest_klass

    @s.save_cache

    refute_file File.join(@tmpdir, 'cache.ri')
  end

  def test_save_cache_duplicate_methods
    @s.save_method @klass, @meth
    @s.save_method @klass, @meth

    @s.save_cache

    assert_cache({ 'Object' => %w[method] }, {}, {}, [])
  end

  def test_save_class
    @s.save_class @klass

    assert_directory File.join(@tmpdir, 'Object')
    assert_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')

    assert_cache nil, nil, nil, %w[Object], 'Object' => OBJECT_ANCESTORS

    assert_equal @klass, @s.load_class('Object')
  end

  def test_save_class_basic_object
    @klass.instance_variable_set :@superclass, nil

    @s.save_class @klass

    assert_directory File.join(@tmpdir, 'Object')
    assert_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')

    assert_cache(nil, nil, nil, %w[Object])

    assert_equal @klass, @s.load_class('Object')
  end

  def test_save_class_delete
    # save original
    @s.save_class @klass
    @s.save_method @klass, @meth
    @s.save_method @klass, @meth_bang
    @s.save_method @klass, @cmeth
    @s.save_cache

    klass = RDoc::NormalClass.new 'Object'

    meth = klass.add_method RDoc::AnyMethod.new(nil, 'replace')
    meth.record_location @top_level

    # load original, save newly updated class
    @s = RDoc::RI::Store.new @tmpdir
    @s.load_cache
    @s.save_class klass
    @s.save_cache

    # load from disk again
    @s = RDoc::RI::Store.new @tmpdir
    @s.load_cache

    @s.load_class 'Object'

    assert_cache({ 'Object' => %w[replace] }, {},
                 { 'Object' => %w[attr_accessor\ attr] }, %w[Object],
                 'Object' => OBJECT_ANCESTORS)

    refute File.exist? @s.method_file(@klass.full_name, @meth.full_name)
    refute File.exist? @s.method_file(@klass.full_name, @meth_bang.full_name)
    refute File.exist? @s.method_file(@klass.full_name, @cmeth.full_name)
  end

  def test_save_class_dry_run
    @s.dry_run = true

    @s.save_class @klass

    refute_file File.join(@tmpdir, 'Object')
    refute_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')
  end

  def test_save_class_merge
    @s.save_class @klass

    klass = RDoc::NormalClass.new 'Object'
    klass.add_comment 'new comment', @top_level

    s = RDoc::RI::Store.new @tmpdir
    s.save_class klass

    s = RDoc::RI::Store.new @tmpdir

    inner = @RM::Document.new @RM::Paragraph.new 'new comment'
    inner.file = @top_level

    document = @RM::Document.new inner

    assert_equal document, s.load_class('Object').comment
  end

  # This is a functional test
  def test_save_class_merge_constant
    store = RDoc::Store.new
    tl = store.add_file 'file.rb'

    klass = tl.add_class RDoc::NormalClass, 'C'
    klass.add_comment 'comment', tl

    const = klass.add_constant RDoc::Constant.new('CONST', nil, nil)
    const.record_location tl

    @s.save_class klass

    # separate parse run, independent store
    store = RDoc::Store.new
    tl = store.add_file 'file.rb'
    klass2 = tl.add_class RDoc::NormalClass, 'C'
    klass2.record_location tl

    s = RDoc::RI::Store.new @tmpdir
    s.save_class klass2

    # separate `ri` run, independent store
    s = RDoc::RI::Store.new @tmpdir

    result = s.load_class 'C'

    assert_empty result.constants
  end

  def test_save_class_methods
    @s.save_class @klass

    assert_directory File.join(@tmpdir, 'Object')
    assert_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')

    assert_cache nil, nil, nil, %w[Object], 'Object' => OBJECT_ANCESTORS

    assert_equal @klass, @s.load_class('Object')
  end

  def test_save_class_nested
    @s.save_class @nest_klass

    assert_directory File.join(@tmpdir, 'Object', 'SubClass')
    assert_file File.join(@tmpdir, 'Object', 'SubClass', 'cdesc-SubClass.ri')

    assert_cache({ 'Object::SubClass' => %w[method] }, {}, {},
                 %w[Object::SubClass], 'Object::SubClass' => %w[Incl Object])
  end

  def test_save_method
    @s.save_method @klass, @meth

    assert_directory File.join(@tmpdir, 'Object')
    assert_file File.join(@tmpdir, 'Object', 'method-i.ri')

    assert_cache({ 'Object' => %w[method] }, {}, {}, [])

    assert_equal @meth, @s.load_method('Object', '#method')
  end

  def test_save_method_dry_run
    @s.dry_run = true

    @s.save_method @klass, @meth

    refute_file File.join(@tmpdir, 'Object')
    refute_file File.join(@tmpdir, 'Object', 'method-i.ri')
  end

  def test_save_method_nested
    @s.save_method @nest_klass, @nest_meth

    assert_directory File.join(@tmpdir, 'Object', 'SubClass')
    assert_file File.join(@tmpdir, 'Object', 'SubClass', 'method-i.ri')

    assert_cache({ 'Object::SubClass' => %w[method] }, {}, {}, [])
  end

end

