require 'test/unit'
require 'json_patterns'
require 'set'

class JsonValidationTest < Test::Unit::TestCase
  def assert_pattern_match(pattern, value, failure_message = nil)
    validation = Validation.new_from_pattern(pattern)
    failures = validation.validate_from_root(value)
    assert_equal [], failures, failure_message
  end

  def assert_pattern_failures(pattern, value, expected_failures, failure_message = nil)
    validation = Validation.new_from_pattern(pattern)
    failures = validation.validate_from_root(value)
    assert_equal expected_failures, failures, failure_message
  end

  def assert_pattern_unexpected(pattern, value, failure_params, failure_message = nil)
    expected_failures = [ValidationUnexpected.new(failure_params)]
    assert_pattern_failures pattern, value, expected_failures, failure_message
  end

  def assert_pattern_ambiguity(pattern, value, failure_params, failure_message = nil)
    expected_failures = [ValidationAmbiguity.new(failure_params)]
    assert_pattern_failures pattern, value, expected_failures, failure_message
  end

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
    assert_pattern_match 'xyz', 'xyz'

    assert_pattern_unexpected 'xyz', 'zyx', {
        path: [],
        found: '"zyx"',
        expected: '"xyz"',
    }

    assert_pattern_unexpected 'xyz', 4, {
        path: [],
        found: 'integer',
        expected: 'string',
    }
  end

  def test_literal_integer_validation
    assert_pattern_match 54, 54

    assert_pattern_unexpected 54, 45, {
        path: [],
        found: '45',
        expected: '54',
    }

    assert_pattern_unexpected 54, 'xyz', {
        path: [],
        found: 'string',
        expected: 'integer',
    }
  end

  def test_literal_float_validation
    assert_pattern_match 54.32, 54.32

    assert_pattern_unexpected 54.32, 23.45, {
        path: [],
        found: '23.45',
        expected: '54.32',
    }

    assert_pattern_unexpected 54.32, 54, {
        path: [],
        found: 'integer',
        expected: 'float',
    }
  end

  def test_regex_match
    pattern = /who+ah/
    validation = Validation.new_from_pattern(pattern)

    assert_pattern_match /who+ah/, 'whoooooah'

    assert_pattern_unexpected /who+ah/, 4, {
        path: [],
        found: 'integer',
        expected: 'string',
    }

    assert_pattern_unexpected /who+ah/, 'whah', {
        path: [],
        found: '"whah"',
        expected: 'string matching /who+ah/',
    }
  end

  def test_email_match
    pattern = Email
    validation = Validation.new_from_pattern(pattern)

    assert_pattern_unexpected Email, 1234, {
        path: [],
        found: 'integer',
        expected: 'string',
    }

    assert_pattern_match Email, 'larry@janrain.com'

    assert_pattern_unexpected Email, '@.', {
        path: [],
        found: '"@."',
        expected: 'email',
    }

    assert_pattern_match Email, '"Larry Drebes"@janrain.com'
  end

  def test_URL_match
    assert_pattern_unexpected URL, 1234, {
        path: [],
        found: 'integer',
        expected: 'string',
    }

    assert_pattern_match URL, 'http://janrain.com'

    assert_pattern_unexpected URL, 'janrain.com', {
        path: [],
        found: '"janrain.com"',
        expected: 'URL',
    }

    assert_pattern_match URL, 'http://warbler.janrain.mobi/products/zumba?238234;3512'

    assert_pattern_match URL, 'ftp://larry:coorslight@ftp.janrain.com'
  end

  def test_literal_nil_match
    assert_pattern_match nil, nil

    assert_pattern_unexpected nil, '', {
        path: [],
        found: 'string',
        expected: 'null',
    }
  end

  def test_uniform_arrays
    pattern = array_of(String)
    validation = Validation.new_from_pattern(pattern)

    assert_pattern_unexpected array_of(String), { "a" => 'b' }, {
        path: [],
        found: 'object',
        expected: 'array',
    }

    assert_pattern_match array_of(String), []

    assert_pattern_failures array_of(String), ['2', 'plus', 3, 'is', 5], [
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
    ]

    assert_pattern_match array_of(String), ['hello', 'to', 'five', 'people']
  end

  def test_uniform_objects
    pattern = { many => String }

    assert_pattern_unexpected pattern, ['a', 'b'], {
      path: [],
      found: 'array',
      expected: 'object',
    }

    assert_pattern_match pattern, {}

    assert_pattern_failures pattern, { "movie" => 'Up', "book" => 12345, "avg" => 46.2 }, [
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
    ]

    assert_pattern_match pattern, { "movie" => 'Up', "book" => 'Twilight' }
  end

  def test_object_with_fixed_names
    pattern = {
      name: String,
      age: Integer,
      registered: Boolean,
    }

    value = {
      "name" => 'Bob',
      "age" => 22,
      "registered" => true,
    }
    assert_pattern_match pattern, value

    value = {
      "name" => 909,
      "age" => 22,
    }
    assert_pattern_failures pattern, value, [
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
    ]
  end

  def test_dispatch_of_case_by_name
    pattern = { one_of => [
        { car: String, numDoors: Integer },
        { bike: String, numSpokes: Integer },
      ]}
    value = { "car" => 'Studebaker', "numDoors" => 4 }
    assert_pattern_match pattern, value

    value = { "bike" => 'Specialized', "numSpokes" => 30 }
    assert_pattern_match pattern, value

    value = { "car" => 'Studebaker', "numSpokes" => 4 }
    assert_pattern_failures pattern, value, [
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
    ]
  end

  def test_dispatch_of_case_by_value
    pattern = { one_of => [
        { model: 'Subaru', numDoors: Integer },
        { model: 'Yamaha', numCylinders: Integer },
      ]}
    value = { "model" => 'Subaru', "numDoors" => 4 }
    assert_pattern_match pattern, value

    value = { "model" => 'Yamaha', "numCylinders" => 4 }
    assert_pattern_match pattern, value

    value = { "model" => 'Yamaha', "numDoors" => 4 }
    assert_pattern_failures pattern, value, [
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
    ]
  end

  def test_validation_with_good_name_but_unrecognized_value
    assert_pattern_unexpected({ life: 'good' }, { "life" => 'bad' }, {
        path: ['life'],
        found: '"bad"',
        expected: '"good"',
    })
  end

  def test_validation_with_complex_incorrect_value
    pattern = { person: { age: Integer, name: String } }
    value = { "person" => ['Ralph', 'Amy'] }

    assert_pattern_unexpected pattern, value, {
        path: ['person'],
        found: 'array',
        expected: 'object',
    }
  end

  def test_validation_with_good_name_and_value_not_matching_pattern
    pattern = one_of({ life: 'good' }, { death: 'bad' })
    value = { "life" => 'bad' }

    assert_pattern_unexpected pattern, value, {
        path: ['life'],
        found: '"bad"',
        expected: Set['"good"'],
    }
  end

  def test_validation_with_alternate_patterns_where_value_may_also_contain_alternate_patterns
    pattern = one_of({ name: one_of('a', 'c') }, { name: one_of('b', 'd') })

    assert_pattern_match pattern, { "name" => 'd' }

    assert_pattern_unexpected pattern, { "name" => 'e' }, {
        path: ['name'],
        found: '"e"',
        expected: Set['"a"', '"c"', '"b"', '"d"'],
    }
  end

  def test_validation_with_nested_alternate_patterns
    pattern = one_of(
      one_of('a', 'b'),
      one_of('c', 'd'),
    )

    ['a', 'b', 'c', 'd'].each do |value|
      assert_pattern_match pattern, value
    end

    assert_pattern_unexpected pattern, "e", {
      path: [],
      found: '"e"',
      expected: Set['"a"', '"b"', '"c"', '"d"'],
    }

    pattern = {
      one_of => [
        { one_of => [{ a: __ }, { b: __ }] },
        { one_of => [{ c: __ }, { d: __ }] },
      ]
    }

    ['a', 'b', 'c', 'd'].each do |name|
      assert_pattern_match pattern, { name => 'x' }
    end

    value = { 'e' => 'x' }
    assert_pattern_failures pattern, { 'e' => 'x' }, [
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
    ]
  end

  def test_validation_with_alternate_object_patterns_inside_alternate_value_patterns
    pattern = one_of('x', one_of({ y: Integer }, { z: String }))

    assert_pattern_match pattern, 'x'

    assert_pattern_match pattern, { "y" => 1 }

    assert_pattern_match pattern, { "z" => "amazing" }

    assert_pattern_unexpected pattern, {}, {
      path: [],
      found: 'end of object members',
      expected: Set['name: "y"', 'name: "z"'],
    }
  end

  def test_validation_of_optional_members
    pattern = { optional => { count: Integer } }

    assert_pattern_match pattern, {}

    assert_pattern_match pattern, { "count" => 3 }

    assert_pattern_unexpected pattern, { "blink" => 3 }, {
        path: [],
        found: 'names: "blink"',
        expected: 'end of object members',
    }

    assert_pattern_unexpected pattern, { "count" => 'x' }, {
        path: ['count'],
        found: 'string',
        expected: 'integer',
    }
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
      assert_pattern_match pattern, { "foo" => 1 }, "pattern ##{pattern_index}"
      assert_pattern_match pattern, { "foo" => 1, "bar" => 2 }, "pattern ##{pattern_index}"
      assert_pattern_match pattern, { "foo" => 1, "baz" => 2 }, "pattern ##{pattern_index}"

      assert_pattern_unexpected pattern, { "foo" => 1, "quux" => 2 }, {
        path: [],
        found: 'names: "quux"',
        expected: 'end of object members',
      }, "pattern ##{pattern_index}"
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
      assert_pattern_unexpected pattern, { "foo" => 1 }, {
        path: [],
        found: 'end of object members',
        expected: Set['name: "bar"', 'name: "baz"'],
      }, "pattern ##{pattern_index}"

      assert_pattern_match pattern, { "foo" => 1, "bar" => 2 }, "pattern ##{pattern_index}"
      assert_pattern_match pattern, { "foo" => 1, "baz" => 2 }, "pattern ##{pattern_index}"

      assert_pattern_failures pattern, { "foo" => 1, "quux" => 2 }, [
        ValidationUnexpected.new(
          path: [],
          found: 'names: "quux"',
          expected: Set['name: "bar"', 'name: "baz"'],
        ),
        ValidationUnexpected.new(
          path: [],
          found: 'names: "quux"',
          expected: 'end of object members',
        ),
      ], "pattern ##{pattern_index}"
    end
  end

  def test_cyclic_value_expression
    pattern = cyclic { |pattern|
      one_of(nil, { left: pattern, right: pattern })
    }

    assert_pattern_match pattern, nil
    assert_pattern_match pattern, { "left" => nil, "right" => nil }

    value = { "left" => { "left" => nil, "right" => nil }, "right" => nil }
    assert_pattern_match pattern, value

    value = { "left" => { "left" => nil, "right" => 1 }, "right" => nil }
    assert_pattern_unexpected pattern, value, {
        path: ['left', 'right'],
        found: '1',
        expected: Set['null', 'object'],
    }
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

    value = {
      "name" => "Tim Cook",
      "address" => '1 Infinite Loop',
      "phone" => '971-555-1212',
    }
    assert_pattern_match pattern, value

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
    assert_pattern_match pattern, value
  end

  def test_using_object_member_patterns_in_value_contexts
    pattern = {
      members => cyclic { |es| {
          foo: Integer,
          optional => { bar: es, baz: String }
        }
      }
    }

    value = {
      "foo" => 1,
      "bar" => {
        "foo" => 2,
        "bar" => { "foo" => 3 },
        "baz" => 'rope',
      },
      "baz" => 'hope',
    }
    assert_pattern_match pattern, value

    pattern = {
      members => cyclic { |es| {
          foo: Integer,
          bar: one_of(es, nil),
        }
      }
    }

    value = {
      "foo" => 1,
      "bar" => {
        "foo" => 2,
        "bar" => nil,
      }
    }
    assert_pattern_match pattern, value
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

    value = {
      "foo" => 1,
      "bar" => 2,
      "baz" => { "foo" => 3, "bar" => 4 },
    }
    assert_pattern_match pattern, value
  end

  def test_ambiguous_patterns
    pattern = one_of(/f.ob/, /fr.b/)

    assert_pattern_ambiguity pattern, "frob", {
      path: [],
      found: '"frob"',
      overlapping_patterns: ['/f.ob/', '/fr.b/'],
    }
  end

  def test_array_with_a_fixed_number_of_values
    # TODO
  end
end
