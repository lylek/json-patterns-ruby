require 'test/unit'
require 'json_patterns'
require 'set'

class JsonValidationTest < Test::Unit::TestCase
  def test_validation_failure_string_and_json_representation
    failure = ValidationUnexpected.new(
        path: ['santa', 'came', 4, 'you'],
        found: "a box of chocolates",
        expected: "two lumps of coal",
    )
    assert_equal(
      "at $['santa']['came'][4]['you']; found a box of chocolates; expected two lumps of coal",
      failure.to_s,
    )
    assert_equal(
      {
        "path" => ['santa', 'came', 4, 'you'],
        "found" => "a box of chocolates",
        "expected" => "two lumps of coal",
      },
      failure.to_json,
    )

    failure = ValidationUnexpected.new(
        path: ['some', 'where'],
        found: 'names: "foo"',
        expected: Set['name: ape'],
    )
    assert_equal(
      "at $['some']['where']; found names: \"foo\"; expected name: ape",
      failure.to_s,
    )
    assert_equal(
      {
        "path" => ['some', 'where'],
        "found" => "names: \"foo\"",
        "expected" => ["name: ape"],
      },
      failure.to_json,
    )

    failure = ValidationUnexpected.new(
        path: ['some', 'where'],
        found: 'names: "foo"',
        expected: Set['name: ape', 'name: boar', 'name: cat'],
      )
    assert_equal(
      "at $['some']['where']; found names: \"foo\"; expected one of: name: ape, name: boar, name: cat",
      failure.to_s,
    )
    assert_equal(
      {
        "path" => ['some', 'where'],
        "found" => "names: \"foo\"",
        "expected" => ["name: ape", "name: boar", "name: cat"],
      },
      failure.to_json,
    )

    failure = ValidationAmbiguity.new(
      path: ['some', 'where'],
      found: '"frob"',
      overlapping_patterns: Set['/f.ob/', '/fr.b/'],
    )
    assert_equal(
      "ambiguous patterns at $['some']['where']; found \"frob\"; overlapping patterns: /f.ob/, /fr.b/",
      failure.to_s,
    )
    assert_equal(
      {
        "path" => ["some", "where"],
        "found" => "\"frob\"",
        "overlapping_patterns" => ["/f.ob/", "/fr.b/"],
      },
      failure.to_json,
    )
  end

  def test_literal_string_validation
    pattern = 'xyz'
    validation = Validation.new_from_pattern(pattern)

    value = 'xyz'
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = 'zyx'
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: '"zyx"',
        expected: '"xyz"',
      )], failures

    value = 4
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'integer',
        expected: 'string',
      )], failures
  end

  def test_literal_integer_validation
    pattern = 54
    validation = Validation.new_from_pattern(pattern)

    value = 54
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = 45
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: '45',
        expected: '54',
      )], failures

    value = 'xyz'
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'string',
        expected: 'integer',
      )], failures
  end

  def test_literal_float_validation
    pattern = 54.32
    validation = Validation.new_from_pattern(pattern)

    value = 54.32
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = 23.45
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: '23.45',
        expected: '54.32',
      )], failures

    value = 54
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'integer',
        expected: 'float',
      )], failures
  end

  def test_regex_match
    pattern = /who+ah/
    validation = Validation.new_from_pattern(pattern)

    value = 'whoooooah'
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = 4
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'integer',
        expected: 'string',
      )], failures

    value = 'whah'
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: '"whah"',
        expected: 'string matching /who+ah/',
      )], failures
  end

  def test_email_match
    pattern = Email
    validation = Validation.new_from_pattern(pattern)

    value = 1234
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'integer',
        expected: 'string',
      )], failures

    value = 1234
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'integer',
        expected: 'string',
      )], failures

    value = 'larry@janrain.com'
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = '@.'
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: '"@."',
        expected: 'email',
      )], failures

    value = '"Larry Drebes"@janrain.com'
    failures = validation.validate_from_root(value)
    assert_equal [], failures
  end

  def test_URL_match
    pattern = URL
    validation = Validation.new_from_pattern(pattern)

    value = 1234
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'integer',
        expected: 'string',
      )], failures

    value = 'http://janrain.com'
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = 'janrain.com'
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: '"janrain.com"',
        expected: 'URL',
      )], failures

    value = 'http://warbler.janrain.mobi/products/zumba?238234;3512'
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = 'ftp://larry:coorslight@ftp.janrain.com'
    failures = validation.validate_from_root(value)
    assert_equal [], failures
  end

  def test_literal_nil_match
    pattern = nil
    validation = Validation.new_from_pattern(pattern)

    value = nil
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = ''
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'string',
        expected: 'null',
      )], failures
  end

  def test_uniform_arrays
    pattern = array_of(String)
    validation = Validation.new_from_pattern(pattern)

    value = { "a" => 'b' }
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'object',
        expected: 'array',
      )], failures

    value = []
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = ['2', 'plus', 3, 'is', 5]
    failures = validation.validate_from_root(value)
    assert_equal [
      ValidationUnexpected.new(
        path: [2],
        found: 'integer',
        expected: 'string',
      ),
      ValidationUnexpected.new(
        path: [4],
        found: 'integer',
        expected: 'string',
      ),
    ], failures

    value = ['hello', 'to', 'five', 'people']
    failures = validation.validate_from_root(value)
    assert_equal [], failures
  end

  def test_uniform_objects
    pattern = { many => String }
    validation = Validation.new_from_pattern(pattern)

    value = ['a', 'b']
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'array',
        expected: 'object',
      )], failures

    value = {}
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "movie" => 'Up', "book" => 12345, "avg" => 46.2 }
    failures = validation.validate_from_root(value)
    assert_equal [
      ValidationUnexpected.new(
        path: ['book'],
        found: 'integer',
        expected: 'string',
      ),
      ValidationUnexpected.new(
        path: ['avg'],
        found: 'float',
        expected: 'string',
      ),
    ], failures

    value = { "movie" => 'Up', "book" => 'Twilight' }
    failures = validation.validate_from_root(value)
    assert_equal [], failures
  end

  def test_object_with_fixed_names
    pattern = {
      name: String,
      age: Integer,
      registered: Boolean,
    }
    validation = Validation.new_from_pattern(pattern)

    value = {
      "name" => 'Bob',
      "age" => 22,
      "registered" => true,
    }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = {
      "name" => 909,
      "age" => 22,
    }
    failures = validation.validate_from_root(value)
    assert_equal [
      ValidationUnexpected.new(
        path: ['name'],
        found: 'integer',
        expected: 'string',
      ),
      ValidationUnexpected.new(
        path: [],
        found: "end of object members",
        expected: 'name: "registered"',
      ),
    ], failures
  end

  def test_dispatch_of_case_by_name
    pattern = { one_of => [
        { car: String, numDoors: Integer },
        { bike: String, numSpokes: Integer },
      ]}
    validation = Validation.new_from_pattern(pattern)
    value = { "car" => 'Studebaker', "numDoors" => 4 }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "bike" => 'Specialized', "numSpokes" => 30 }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "car" => 'Studebaker', "numSpokes" => 4 }
    failures = validation.validate_from_root(value)
    assert_equal [
      ValidationUnexpected.new(
        path: [],
        found: 'names: "numSpokes"',
        expected: 'name: "numDoors"',
      ),
      ValidationUnexpected.new(
        path: [],
        found: 'names: "numSpokes"',
        expected: 'end of object members',
      ),
    ], failures
  end

  def test_dispatch_of_case_by_value
    pattern = { one_of => [
        { model: 'Subaru', numDoors: Integer },
        { model: 'Yamaha', numCylinders: Integer },
      ]}
    validation = Validation.new_from_pattern(pattern)
    value = { "model" => 'Subaru', "numDoors" => 4 }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "model" => 'Yamaha', "numCylinders" => 4 }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "model" => 'Yamaha', "numDoors" => 4 }
    failures = validation.validate_from_root(value)
    assert_equal [
      ValidationUnexpected.new(
        path: [],
        found: 'names: "numDoors"',
        expected: 'name: "numCylinders"',
      ),
      ValidationUnexpected.new(
        path: [],
        found: 'names: "numDoors"',
        expected: 'end of object members',
      ),
    ], failures
  end

  def test_validation_with_good_name_but_unrecognized_value
    pattern = { life: 'good' }
    validation = Validation.new_from_pattern(pattern)

    value = { "life" => 'bad' }
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: ['life'],
        found: '"bad"',
        expected: '"good"',
      )], failures
  end

  def test_validation_with_complex_incorrect_value
    pattern = { person: { age: Integer, name: String } }
    validation = Validation.new_from_pattern(pattern)

    value = { "person" => ['Ralph', 'Amy'] }
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: ['person'],
        found: 'array',
        expected: 'object',
      )], failures
  end

  def test_validation_with_good_name_and_value_not_matching_pattern
    pattern = one_of({ life: 'good' }, { death: 'bad' })
    validation = Validation.new_from_pattern(pattern)

    value = { "life" => 'bad' }
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: ['life'],
        found: '"bad"',
        expected: Set['"good"'],
      )], failures
  end

  def test_validation_with_alternate_patterns_where_value_may_also_contain_alternate_patterns
    pattern = one_of({ name: one_of('a', 'c') }, { name: one_of('b', 'd') })
    validation = Validation.new_from_pattern(pattern)

    value = { "name" => 'd' }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "name" => 'e' }
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: ['name'],
        found: '"e"',
        expected: Set['"a"', '"c"', '"b"', '"d"'],
      )], failures
  end

  def test_validation_with_nested_alternate_patterns
    pattern = one_of(
      one_of('a', 'b'),
      one_of('c', 'd'),
    )
    validation = Validation.new_from_pattern(pattern)

    ['a', 'b', 'c', 'd'].each do |value|
      failures = validation.validate_from_root(value)
      assert_equal [], failures
    end

    value = "e"
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
      path: [],
      found: '"e"',
      expected: Set['"a"', '"b"', '"c"', '"d"'],
    )], failures

    pattern = {
      one_of => [
        { one_of => [{ a: __ }, { b: __ }] },
        { one_of => [{ c: __ }, { d: __ }] },
      ]
    }
    validation = Validation.new_from_pattern(pattern)

    ['a', 'b', 'c', 'd'].each do |name|
      failures = validation.validate_from_root({ name => 'x' })
      assert_equal [], failures
    end

    value = { 'e' => 'x' }
    failures = validation.validate_from_root(value)
    assert_equal [
      ValidationUnexpected.new(
        path: [],
        found: 'names: "e"',
        # TODO: Factor out the 'names' (names: a, b, c, d)
        expected: Set['name: "a"', 'name: "b"', 'name: "c"', 'name: "d"'],
      ),
      ValidationUnexpected.new(
        path: [],
        found: 'names: "e"',
        expected: 'end of object members',
      ),
    ], failures
  end

  def test_validation_with_alternate_object_patterns_inside_alternate_value_patterns
    pattern = one_of('x', one_of({ y: Integer }, { z: String }))
    validation = Validation.new_from_pattern(pattern)

    value = 'x'
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "y" => 1 }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "z" => "amazing" }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = {}
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
      path: [],
      found: 'end of object members',
      expected: Set['name: "y"', 'name: "z"'],
    )], failures
  end

  def test_validation_of_optional_members
    pattern = { optional => { count: Integer } }
    validation = Validation.new_from_pattern(pattern)

    value = {}
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "count" => 3 }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "blink" => 3 }
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: [],
        found: 'names: "blink"',
        expected: 'end of object members',
      )], failures

    value = { "count" => 'x' }
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: ['count'],
        found: 'string',
        expected: 'integer',
      )], failures
  end

  def test_optional_disjunction
    patterns = [
      {
        foo: Integer,
        optional => {
          one_of => [
            { bar: Integer },
            { baz: Integer },
          ]
        }
      },
      {
        foo: Integer,
        optional => one_of(
          { bar: Integer },
          { baz: Integer },
        ),
      },
    ]

    patterns.each_with_index do |pattern, pattern_index|
      validation = Validation.new_from_pattern(pattern)

      value = { "foo" => 1 }
      failures = validation.validate_from_root(value)
      assert_equal [], failures, "pattern ##{pattern_index}"

      value = { "foo" => 1, "bar" => 2 }
      failures = validation.validate_from_root(value)
      assert_equal [], failures, "pattern ##{pattern_index}"

      value = { "foo" => 1, "baz" => 2 }
      failures = validation.validate_from_root(value)
      assert_equal [], failures, "pattern ##{pattern_index}"

      value = { "foo" => 1, "quux" => 2 }
      failures = validation.validate_from_root(value)
      assert_equal [ValidationUnexpected.new({
        path: [],
        found: 'names: "quux"',
        expected: 'end of object members',
      })], failures, "pattern ##{pattern_index}"
    end
  end

  def test_disjunction_in_member_context
    patterns = [
      {
        foo: Integer,
        members => {
          one_of => [
            { bar: Integer },
            { baz: Integer },
          ]
        }
      },
      {
        foo: Integer,
        members => one_of(
          { bar: Integer },
          { baz: Integer },
        ),
      },
    ]

    patterns.each_with_index do |pattern, pattern_index|
      validation = Validation.new_from_pattern(pattern)

      value = { "foo" => 1 }
      failures = validation.validate_from_root(value)
      assert_equal [ValidationUnexpected.new({
        path: [],
        found: 'end of object members',
        expected: Set['name: "bar"', 'name: "baz"'],
      })], failures, "pattern ##{pattern_index}"

      value = { "foo" => 1, "bar" => 2 }
      failures = validation.validate_from_root(value)
      assert_equal [], failures, "pattern ##{pattern_index}"

      value = { "foo" => 1, "baz" => 2 }
      failures = validation.validate_from_root(value)
      assert_equal [], failures, "pattern ##{pattern_index}"

      value = { "foo" => 1, "quux" => 2 }
      failures = validation.validate_from_root(value)
      assert_equal [
        ValidationUnexpected.new({
          path: [],
          found: 'names: "quux"',
          expected: Set['name: "bar"', 'name: "baz"'],
        }),
        ValidationUnexpected.new({
          path: [],
          found: 'names: "quux"',
          expected: 'end of object members',
        }),
      ], failures, "pattern ##{pattern_index}"
    end
  end

  def test_cyclic_value_expression
    pattern = cyclic { |pattern|
      one_of(nil, { left: pattern, right: pattern })
    }
    validation = Validation.new_from_pattern(pattern)

    value = nil
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "left" => nil, "right" => nil }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "left" => { "left" => nil, "right" => nil }, "right" => nil }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = { "left" => { "left" => nil, "right" => 1 }, "right" => nil }
    failures = validation.validate_from_root(value)
    assert_equal [ValidationUnexpected.new(
        path: ['left', 'right'],
        found: '1',
        expected: Set['null', 'object'],
      )], failures
  end

  def test_cyclic_object_members_expression
    deets = cyclic { |deets| {
      address: String,
      phone: String,
      optional => {
        friend: {
          friendName: String,
          members => deets,
        }
      }
    }}
    pattern = {
      name: String,
      members => deets,
    }
    validation = Validation.new_from_pattern(pattern)

    value = {
      "name" => "Tim Cook",
      "address" => '1 Infinite Loop',
      "phone" => '971-555-1212',
    }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    value = {
      "name" => "Tim Cook",
      "address" => '1 Infinite Loop',
      "phone" => '971-555-1212',
      "friend" => {
        "friendName" => "Bill Gates",
        "address" => '2 Blue Screen Way',
        "phone" => '241-555-1212',
      }
    }
    failures = validation.validate_from_root(value)
    assert_equal [], failures
  end

  def test_using_object_member_patterns_in_value_contexts
    pattern = {
      members => cyclic { |es| {
          foo: Integer,
          optional => { bar: es, baz: String }
        }
      }
    }
    validation = Validation.new_from_pattern(pattern)

    value = {
      "foo" => 1,
      "bar" => {
        "foo" => 2,
        "bar" => { "foo" => 3 },
        "baz" => 'rope',
      },
      "baz" => 'hope',
    }
    failures = validation.validate_from_root(value)
    assert_equal [], failures

    pattern = {
      members => cyclic { |es| {
          foo: Integer,
          bar: one_of(es, nil),
        }
      }
    }
    validation = Validation.new_from_pattern(pattern)

    value = {
      "foo" => 1,
      "bar" => {
        "foo" => 2,
        "bar" => nil,
      }
    }
    failures = validation.validate_from_root(value)
    assert_equal [], failures
  end

  def test_using_object_patterns_in_object_member_contexts
    object = {
      foo: Integer,
      bar: Integer,
    }
    pattern = {
      baz: object,
      members => object,
    }
    validation = Validation.new_from_pattern(pattern)

    value = {
      "foo" => 1,
      "bar" => 2,
      "baz" => { "foo" => 3, "bar" => 4 },
    }
    failures = validation.validate_from_root(value)
    assert_equal [], failures
  end

  def test_ambiguous_patterns
    pattern = one_of(/f.ob/, /fr.b/)
    validation = Validation.new_from_pattern(pattern)

    value = "frob"
    failures = validation.validate_from_root(value)
    assert_equal [ValidationAmbiguity.new(
      path: [],
      found: '"frob"',
      overlapping_patterns: ['/f.ob/', '/fr.b/'],
    )], failures
  end

  def test_array_with_a_fixed_number_of_values
    # TODO
  end
end
