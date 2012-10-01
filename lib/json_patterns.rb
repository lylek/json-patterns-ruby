require 'set'

def set_union(sets)
  sets.reduce { |u, s| u + s }
end

module HashInitialized
  def initialize(opts={})
    opts.each { |k, v|

      # TODO: No guarantee that the method is really a reader for that attribute - this would be
      #   better handled with a specialized attribute maker.

      raise "class #{self.class} has no attribute #{k.inspect}" unless self.respond_to?(k)
      self.instance_variable_set("@#{k}", v)
    }
  end
end

module DeepEquality
  def ==(other)
    self.class == other.class and
      self.instance_variables.map { |v| self.instance_variable_get(v) } ==
      other.instance_variables.map { |v| other.instance_variable_get(v) }
  end
end

module Inspectable # because overriding #to_s unfortunately wipes out #inspect
  INSPECTING_KEY = ('Inspectable::' + '%016x' % rand(2**64)).to_sym

  def inspect
    Thread.current[INSPECTING_KEY] ||= {}

    object_desc = "#{self.class}:0x#{(object_id << 1).to_s(16)}"

    if Thread.current[INSPECTING_KEY][self]
      attributes_desc = ' ...'
    else
      Thread.current[INSPECTING_KEY][self] = true

      begin
        attributes_desc = self.instance_variables.map { |v|
          " #{v.to_s}=#{instance_variable_get(v).inspect}"
        }.join
      ensure
        Thread.current[INSPECTING_KEY].delete(self)
      end
    end

    return "#<#{object_desc}#{attributes_desc}>"
  end
end

# Dummy classes for patterns

class Boolean; end
class Email; end
class URL; end

class DisjunctionPattern
  include HashInitialized, Inspectable

  attr_accessor :alternatives

  def to_s
    "one_of(#{alternatives.join(', ')})"
  end
end

class DisjunctionKey
end

def one_of(*patterns)
  case patterns
  when []
    DisjunctionKey.new
  else
    DisjunctionPattern.new(alternatives: patterns)
  end
end

class UniformArrayPattern
  include HashInitialized, Inspectable

  attr_accessor :value

  def to_s
    "array_of(#{value})"
  end
end

def array_of(value)
  UniformArrayPattern.new(value: value)
end

class AnythingPattern
  include Inspectable

  def to_s
    '__'
  end
end

def __
  AnythingPattern.new
end

class CyclicPattern
  include Inspectable

  attr_accessor :interior

  # TODO: define to_s
end

def cyclic(&proc)
  p = CyclicPattern.new
  p.interior = proc.call(p)
  return p
end

class JsonType
  include DeepEquality, Inspectable

  attr_reader :type

  def initialize(type)
    @type = type
  end

  def to_s
    @type.to_s
  end

  def self.new_from_value(value)
    case value
    when Hash
      JsonType.new :object
    when Array
      JsonType.new :array
    when String
      JsonType.new :string
    when Integer
      JsonType.new :integer
    when Float
      JsonType.new :float
    when TrueClass
      JsonType.new :boolean
    when FalseClass
      JsonType.new :boolean
    when NilClass
      JsonType.new :null
    else
      raise "value has no JsonType: #{value.inspect}"
    end
  end

  def self.new_from_class(klass)
    case klass.name
    when 'Hash'
      JsonType.new :object
    when 'Array'
      JsonType.new :array
    when 'String'
      JsonType.new :string
    when 'Integer'
      JsonType.new :integer
    when 'Float'
      JsonType.new :float
    when 'Numeric'
      JsonType.new :float
    when 'Boolean'
      JsonType.new :boolean
    when 'NilClass'
      JsonType.new :null
    else
      raise "class has no JsonType: #{klass}"
    end
  end

  def ===(value)
    value_type = JsonType.new_from_value(value).type
    value_type == @type or (value_type == 'number' and (@type == :integer or @type == :float))
  end
end

def json_type_name(value)
  JsonType.new_from_value(value).type.to_s
end

def shallow_value(value)
  case value
  when Hash
    'object'
  when Array
    'array'
  when NilClass
    'null'
  else
    value.inspect
  end
end

class ObjectMembersValidationResult
  include HashInitialized

  attr_reader :failures, :remainder
end

class ValidationFailure
  include HashInitialized, DeepEquality, Inspectable

  attr_reader :path

  def to_json
    Hash[*self.instance_variables.map { |var|
      val = self.instance_variable_get(var)
      [var.to_s.sub('@', ''), (val.is_a?(Set) ? val.to_a : val)]
    }.reduce(:+)]
  end

  def path_to_s
    '$' + @path.map { |p| "[#{ p.is_a?(String) ? "'#{p.to_s}'" : p.to_s }]" }.join('')
  end
end

class ValidationUnexpected < ValidationFailure
  attr_reader :expected, :found

  def to_s
    expected = @expected.is_a?(Set) ?
    (@expected.size == 1 ? @expected.to_a[0] : "one of: " + @expected.to_a.join(', ')) :
      @expected
    return "at #{path_to_s}; found #{@found}; expected #{expected}"
  end
end

class ValidationAmbiguity < ValidationFailure
  attr_reader :found, :overlapping_patterns

  def to_s
    overlapping_patterns = @overlapping_patterns.to_a.join(', ')
    return "ambiguous patterns at #{path_to_s}; found #{@found}; overlapping patterns: #{overlapping_patterns}"
  end
end

class Validation
  include HashInitialized, DeepEquality, Inspectable

  def shallow_match?(data)
    validate([], data).empty?
  end

  def shallow_describe
    Set[to_s]
  end

  def validate_from_root(data)
    validate([], data)
  end

  def self.new_from_pattern(pattern)
    self.memoized_new_from_pattern({}, pattern)
  end

  def self.memoized_new_from_pattern(translation, pattern)
    return translation[pattern.object_id] if translation[pattern.object_id]

    # The below could get stuck in an infinite loop, but only if the pattern
    #   writer is particularly mischievous, doing a deliberate assigment of the
    #   interior of a pattern back to itself.

    if pattern.is_a?(CyclicPattern)
      return memoized_new_from_pattern(translation, pattern.interior)
    end

    case pattern
    when {}
      v = ObjectValidation.new(members: EmptyObjectMembersValidation.new)
    when Hash
      v = ObjectValidation.new(members: nil)
    when UniformArrayPattern
      v = UniformArrayValidation.new
    when DisjunctionPattern
      v = DisjunctionValidation.new
    when Regexp
      v = RegexpValidation.new(regexp: pattern.dup)
    when JsonType
      v = PrimitiveTypeValidation.new(type: pattern.dup)
    when Symbol
      v = PrimitiveTypeValidation.new(type: JsonType.new(pattern))
    when Class
      if pattern == Email
        v = EmailValidation.new
      elsif pattern == URL
        v = URLValidation.new
      else
        v = PrimitiveTypeValidation.new(type: JsonType.new_from_class(pattern))
      end
    when String
      v = PrimitiveValueValidation.new(value: pattern.dup)
    when Numeric
      v = PrimitiveValueValidation.new(value: pattern)
    when TrueClass
      v = PrimitiveValueValidation.new(value: pattern)
    when FalseClass
      v = PrimitiveValueValidation.new(value: pattern)
    when NilClass
      v = PrimitiveValueValidation.new(value: pattern)
    when AnythingPattern
      v = AnythingValidation.new
    else
      raise "Unrecognized type in pattern: #{pattern.class}"
    end

    translation[pattern.object_id] = v

    case pattern
    when {}
    when Hash
      v.members = ObjectMembersValidation.memoized_new_from_pattern(translation, pattern)
    when UniformArrayPattern
      v.value_validation = memoized_new_from_pattern(translation, pattern.value)
    when DisjunctionPattern
      v.alternatives = pattern.alternatives.map { |a| memoized_new_from_pattern(translation, a) }
    end

    return v
  end

  def expects_an_object?
    false
  end

  def as_object_members
    raise "attempted to treat non-object validation as object members: #{self}"
  end
end

class DisjunctionValidation < Validation
  # This is an abstract version that, at run time, becomes either:
  #   when all alternatives are objects -> An ObjectValidation containing an ObjectMembersDisjunctionValidation
  #   otherwise -> a ValueDisjunctionValidation

  # TODO: Do this as a separate transformation step when compiling the validation

  attr_accessor :alternatives

  # TODO: Use some sort of delegator to handle these methods?

  def validate(path, data)
    concrete_validation.validate(path, data)
  end

  def shallow_match?(data)
    concrete_validation.shallow_match?(data)
  end

  def shallow_describe
    concrete_validation.shallow_describe
  end

  def to_s
    concrete_validation.to_s
  end

  def concrete_validation
    @concrete_validation ||= expects_an_object? ?
      ObjectValidation.new(members: as_object_members) :
      ValueDisjunctionValidation.new(alternatives: @alternatives)
  end

  def expects_an_object?
    @alternatives.all? { |v| v.expects_an_object? }
  end

  def as_object_members
    ObjectMembersDisjunctionValidation.new(
      alternatives: @alternatives.map { |v| v.as_object_members }
    )
  end
end

class ValueDisjunctionValidation < Validation
  attr_accessor :alternatives

  def validate(path, data)
    matching = @alternatives.select { |v| v.shallow_match? data }
    if matching.length == 0
      return [ValidationUnexpected.new(
        path: path,
        found: shallow_value(data),
        expected: shallow_describe,
      )]
    elsif matching.length == 1
      return matching[0].validate(path, data)
    else
      return [ValidationAmbiguity.new(
        path: path,
        found: shallow_value(data),
        overlapping_patterns: matching.flat_map { |v| v.shallow_describe.to_a },
      )]
    end
  end

  def shallow_match?(data)
    matching = @alternatives.select { |v| v.shallow_match? data }
    return matching.length == 1
  end

  def shallow_describe
    set_union(@alternatives.map { |v| v.shallow_describe })
  end

  def to_s
    '(' + (@alternatives.map { |v| v.to_s }).join(' | ') + ')'
  end
end

class DisjunctionKey
end

def one_of(*patterns)
  case patterns
  when []
    DisjunctionKey.new
  else
    DisjunctionPattern.new(alternatives: patterns)
  end
end

class UniformArrayValidation < Validation
  attr_accessor :value_validation

  def validate(path, data)
    if data.is_a? Array
      return validate_members(path, data)
    else
      return [ValidationUnexpected.new(
        path: path,
        expected: 'array',
        found: json_type_name(data),
      )]
    end
  end

  def shallow_match?(data)
    data.is_a? Array
  end

  def shallow_describe
    Set['array']
  end

  def to_s
    "[ #{@value_validation}, ... ]"
  end

  private

  def validate_members(path, data)
    failures = []
    for i in 0..(data.length-1)
      failures += @value_validation.validate(path + [i], data[i])
    end
    return failures
  end
end

class ObjectValidation < Validation
  attr_accessor :members

  def validate(path, data)
    if data.is_a? Hash
      result = @members.validate_members(path, data)
      failures = result.failures
      if result.remainder.length > 0
        failures << ValidationUnexpected.new(
          path: path,
          expected: 'end of object members',
          found: "names: " + result.remainder.keys.map { |name| name.inspect }.join(', ')
        )
      end
      return failures
    else
      return [ValidationUnexpected.new(
        path: path,
        expected: 'object',
        found: json_type_name(data),
      )]
    end
  end

  def shallow_match?(data)
    data.is_a? Hash
  end

  def shallow_describe
    Set['object']
  end

  def to_s
    "{ #{@members} }"
  end

  def expects_an_object?
    true
  end

  def as_object_members
    @members
  end
end

class ObjectMembersValidation
  include HashInitialized, Inspectable

  def self.memoized_new_from_pattern(translation, pattern)
    case pattern
    when Hash
      validation = pattern.to_a.reverse.reduce(EmptyObjectMembersValidation.new) do |es, e|
        (name, value) = e
        name = name.to_s if name.is_a? Symbol
        case name
        when String
          value_validation = Validation.memoized_new_from_pattern(translation, value)
          v = SingleObjectMemberValidation.new(name: name, value_validation: value_validation)
        when DisjunctionKey
          unless value.is_a?(Array)
            raise "one_of should only be used with an array"
          end
          vals = value.map { |pat|
            ObjectMembersFromObjectValidation.new(object_validation:
              Validation.memoized_new_from_pattern(translation, pat)
            )
          }
          v = ObjectMembersDisjunctionValidation.new(alternatives: vals)
        when OptionalKey
          v = OptionalObjectMembersValidation.new(members:
            ObjectMembersFromObjectValidation.new(object_validation:
              Validation.memoized_new_from_pattern(translation, value)
            )
          )
        when ManyKey
          v = ManyObjectMembersValidation.new(
            value_validation: Validation.memoized_new_from_pattern(translation, value)
          )
        when MembersKey
          v = ObjectMembersFromObjectValidation.new(
            object_validation: Validation.memoized_new_from_pattern(translation, value)
          )
        else
          raise "unrecognized key type in pattern: #{name.class}"
        end
        SequencedObjectMembersValidation.new(left: v, right: es)
      end
    else
      raise "cannot create object members validation from a #{pattern.class}"
    end
  end
end

class ObjectMembersFromObjectValidation < ObjectMembersValidation
  # represents a type coercion from an ObjectValidation to and ObjectMembersValidation

  # TODO: Do this as a separate transformation step when compiling the validation

  attr_reader :object_validation

  # TODO: Use some sort of delegator to handle these methods?

  def possible_first_names
    as_object_members.possible_first_names
  end

  def first_value_validations(name)
    as_object_members.first_value_validations(name)
  end

  def matching_first_names(data)
    as_object_members.matching_first_names(data)
  end

  def first_value_match?(name, value)
    as_object_members.first_value_match?(name, value)
  end

  def validate_members(path, data)
    as_object_members.validate_members(path, data)
  end

  def to_s
    as_object_members.to_s
  end

  def as_object_members
    @object_members_validation ||= @object_validation.as_object_members
  end
end

class ObjectMembersDisjunctionValidation < ObjectMembersValidation
  attr_accessor :alternatives

  def possible_first_names
    set_union(@alternatives.map { |v| v.possible_first_names })
  end

  def first_value_validations(name)
    set_union(@alternatives.map { |v| v.first_value_validations(name) })
  end

  def matching_first_names(data)
    set_union(@alternatives.map { |v| v.matching_first_names(data) })
  end

  def first_value_match?(name, value)
    @alternatives.any? { |v| v.first_value_match?(name, value) }
  end

  def validate_members(path, data)
    matching_first_names_by_validation =
      Hash[*@alternatives.flat_map { |v| [v, v.matching_first_names(data)] }]
    validations_with_matching_first_names =
      matching_first_names_by_validation.select { |k, v| v.size > 0 }.keys
    matching_names = set_union(matching_first_names_by_validation.values)

    if matching_names.size == 0
      found_names = data.empty? ?
        'end of object members' :
        "names: #{data.keys.map { |name| name.inspect }.join(', ')}"
      return ObjectMembersValidationResult.new(
        failures: [ValidationUnexpected.new(
          path: path,
          found: found_names,
          expected: Set[*possible_first_names.map { |n| "name: #{n.inspect}" }],
        )],
        remainder: data,
      )
    elsif matching_names.size > 1
      return ObjectMembersValidationResult.new(
        failures: [ValidationAmbiguity.new(
          path: path,
          found: data.keys,
          overlapping_patterns: validations_with_matching_first_names.flat_map { |v|
            v.possible_first_names.to_a
          },
        )]
      )
    else
      name = matching_names.to_a[0]
      value = data[name]
      remainder = data.dup
      remainder.delete name
      validations_matching_value =
        validations_with_matching_first_names.select { |v| v.first_value_match?(name, value) }
      if validations_matching_value.length == 0
        return ObjectMembersValidationResult.new(
          failures: [ValidationUnexpected.new(
            path: path + [name],
            found: shallow_value(data[name]),
            expected: set_union(validations_with_matching_first_names.map { |v|
              set_union(v.first_value_validations(name).map { |v| v.shallow_describe })
            }),
          )],
          remainder: remainder,
        )
      elsif validations_matching_value.length == 1
        return validations_matching_value[0].validate_members(path, data)
      else
        return ObjectMembersValidationResult.new(
          failures: [ValidationAmbiguity.new(
            path: path + [name],
            found: shallow_value(data[name]),
            overlapping_patterns: validations_matching_value.flat_map { |v|
              v.first_value_validations(name).shallow_describe.to_a
            },
          )],
          remainder: remainder,
        )
      end
    end
  end

  def to_s
    '(' + (@alternatives.map { |v| v.to_s }).join(' | ') + ')'
  end
end

class SequencedObjectMembersValidation < ObjectMembersValidation
  # TODO: Use an array instead of :left and :right. Easier to process, easier to inspect.
  #   Obviates the need for an EmptyObjectMembersValidation in some cases.

  attr_accessor :left, :right

  def possible_first_names
    @left.possible_first_names
  end

  def first_value_validation
    @left.first_value_validation
  end

  def matching_first_names(data)
    @left.matching_first_names(data)
  end

  def first_value_match?(name, value)
    @left.first_value_match?(name, value)
  end

  def first_value_validations(name)
    @left.first_value_validations(name)
  end

  def validate_members(path, data)
    result_left = @left.validate_members(path, data)
    result_right = @right.validate_members(path, result_left.remainder)
    return ObjectMembersValidationResult.new(
      failures: result_left.failures + result_right.failures,
      remainder: result_right.remainder,
    )
  end

  def to_s
    [@left.to_s, @right.to_s].select { |s| not s.empty? }.join(', ')
  end
end

class EmptyObjectMembersValidation < ObjectMembersValidation
  # TODO: Handle first_name/value methods?

  def validate_members(path, data)
    ObjectMembersValidationResult.new(
      failures: [],
      remainder: data,
    )
  end

  def to_s
    ''
  end
end

class SingleObjectMemberValidation < ObjectMembersValidation
  attr_accessor :name, :value_validation

  def possible_first_names
    Set[@name]
  end

  def first_value_validation
    @value_validation
  end

  def matching_first_names(data)
    data.has_key?(@name) ? Set[@name] : Set[]
  end

  def first_value_match?(name, value)
    return false unless name == @name
    @value_validation.shallow_match?(value)
  end

  def first_value_validations(name)
    Set[@value_validation]
  end

  def validate_members(path, data)
    if data.has_key? @name
      failures = @value_validation.validate(path + [@name], data[@name])
      remainder = data.dup
      remainder.delete @name
      return ObjectMembersValidationResult.new(
        failures: failures,
        remainder: remainder,
      )
    else
      found_names = data.empty? ?
        'end of object members' :
        "names: #{data.keys.map { |name| name.inspect }.join(', ')}"
      return ObjectMembersValidationResult.new(
        failures: [ValidationUnexpected.new(
          path: path,
          expected: "name: \"#@name\"",
          found: found_names,
        )],
        remainder: data,
      )
    end
  end

  def to_s
    "\"#{@name}\": #{@value_validation}"
  end
end

class OptionalObjectMembersValidation < ObjectMembersValidation
  attr_accessor :members

  # TODO: If this is in a sequence, failure should trigger a check to the next member in the sequence

  def possible_first_names
    @members.possible_first_names
  end

  def matching_first_names(data)
    @members.matching_first_names(data)
  end

  def first_value_match?(name, value)
    @members.first_value_match?(name, value)
  end

  def first_value_validations(name)
    @members.first_value_validations(name)
  end

  def validate_members(path, data)
    if matching_first_names(data).size > 0
      return @members.validate_members(path, data)
    else
      return ObjectMembersValidationResult.new(
        failures: [],
        remainder: data,
      )
    end
  end

  def to_s
    "(#{@members})?"
  end
end

class OptionalKey
end

def optional
  OptionalKey.new
end

class ManyObjectMembersValidation < ObjectMembersValidation
  attr_accessor :value_validation

  def possible_first_names
    # TODO: Need a way to indicate this can match any first names, rather than none
    Set[]
  end

  def matching_first_names(data)
    Set[*data.keys]
  end

  def first_value_match?(name, value)
    @value_validation.validate([], value).empty?
  end

  def first_value_validations(name)
    Set[@value_validation]
  end

  def to_s
    "__: #{@value_validation}, ..."
  end

  def validate_members(path, data)
    failures = []
    data = data.to_a
    for i in 0..(data.length-1)
      failures += @value_validation.validate(path + [data[i][0]], data[i][1])
    end
    return ObjectMembersValidationResult.new(
      failures: failures,
      remainder: {},
    )
  end
end

class ManyKey
end

def many
  ManyKey.new
end

class CyclicValueValidation < Validation
  attr_accessor :interior
  @@references = {}
  @@count = 0

  def initialize(opts)
    super(opts)
    @@count += 1
    @@references[self] = @@count
  end

  def validate(path, data)
    interior.validate(path, data)
  end

  def shallow_match?(data)
    interior.shallow_match?(data)
  end

  def shallow_describe
    interior.shallow_describe
  end

  def to_s
    # TODO: Use a dynamically scoped variable to distinguish the first printing of this value

    "&#{@@references[self]}"
  end
end

class MembersKey
end

def members
  MembersKey.new
end

class CyclicObjectMembersValidation < ObjectMembersValidation
  attr_accessor :members
  @@references = {}
  @@count = 0

  def initialize(opts)
    super(opts)
    @@count += 1
    @@references[self] = @@count
  end

  def possible_first_names
    @members.possible_first_names
  end

  def matching_first_names(data)
    @members.matching_first_names(data)
  end

  def first_value_match?(name, value)
    @members.first_value_match?(name, value)
  end

  def first_value_validations(name)
    @members.first_value_validations(name)
  end

  def validate_members(path, data)
    @members.validate_members(path, data)
  end

  def to_s
    "&:#{@@references[self]}"
  end
end

class RegexpValidation < Validation
  attr_accessor :regexp

  def validate(path, data)
    if data.is_a? String
      if data =~ regexp
        return []
      else
        return [ValidationUnexpected.new(
          path: path,
          expected: "string matching #{@regexp.inspect}",
          found: data.inspect,
        )]
      end
    else
      return [ValidationUnexpected.new(path: path, expected: 'string', found: json_type_name(data))]
    end
  end

  def to_s
    @regexp.inspect
  end
end

class EmailValidation < Validation
  # TODO: Replace this with a conjunction of RegexpValidations with customized errors?

  @@email_regexp = Regexp::new("^" +
    # local name
    "(?:" +
    "(?:(?:[a-z\\u00a1-\\uffff0-9]+-?)*[a-z\\u00a1-\\uffff0-9]+)" +
    "|" +
    "(?:\"[^\"]+\")" +
    ")" +
    "@" +
    # host name
    "(?:(?:[a-z\\u00a1-\\uffff0-9]+-?)*[a-z\\u00a1-\\uffff0-9]+)" +
    # domain name
    "(?:\\.(?:[a-z\\u00a1-\\uffff0-9]+-?)*[a-z\\u00a1-\\uffff0-9]+)*" +
    # TLD identifier
    "(?:\\.(?:[a-z\\u00a1-\\uffff]{2,}))" +
    "$", true
  )

  def validate(path, data)
    if data.is_a? String
      if data =~ @@email_regexp
        return []
      else
        return [ValidationUnexpected.new(
          path: path,
          expected: "email",
          found: data.inspect,
        )]
      end
    else
      return [ValidationUnexpected.new(
        path: path,
        expected: 'string',
        found: json_type_name(data),
      )]
    end
  end

  def to_s
    'email'
  end
end

class URLValidation < Validation
  # TODO: Replace this with a conjunction of RegexpValidations with customized errors?

  @@url_regexp = Regexp::new("^" +
    # protocol identifier
    "(?:(?:https?|ftp)://)" +
    # user:pass authentication
    "(?:\\S+(?::\\S*)?@)?" +
    "(?:" +
    # IP address exclusion
    # private & local networks
    "(?!10(?:\\.\\d{1,3}){3})" +
    "(?!127(?:\\.\\d{1,3}){3})" +
    "(?!169\\.254(?:\\.\\d{1,3}){2})" +
    "(?!192\\.168(?:\\.\\d{1,3}){2})" +
    "(?!172\\.(?:1[6-9]|2\\d|3[0-1])(?:\\.\\d{1,3}){2})" +
    # IP address dotted notation octets
    # excludes loopback network 0.0.0.0
    # excludes reserved space >= 224.0.0.0
    # excludes network & broadcast addresses
    # (first & last IP address of each class)
    "(?:[1-9]\\d?|1\\d\\d|2[01]\\d|22[0-3])" +
    "(?:\\.(?:1?\\d{1,2}|2[0-4]\\d|25[0-5])){2}" +
    "(?:\\.(?:[1-9]\\d?|1\\d\\d|2[0-4]\\d|25[0-4]))" +
    "|" +
    # host name
    "(?:(?:[a-z\\u00a1-\\uffff0-9]+-?)*[a-z\\u00a1-\\uffff0-9]+)" +
    # domain name
    "(?:\\.(?:[a-z\\u00a1-\\uffff0-9]+-?)*[a-z\\u00a1-\\uffff0-9]+)*" +
    # TLD identifier
    "(?:\\.(?:[a-z\\u00a1-\\uffff]{2,}))" +
    ")" +
    # port number
    "(?::\\d{2,5})?" +
    # resource path
    "(?:/[^\\s]*)?" +
    "$", true
    )

  def validate(path, data)
    if data.is_a? String
      if data =~ @@url_regexp
        return []
      else
        return [ValidationUnexpected.new(
          path: path,
          expected: "URL",
          found: data.inspect,
        )]
      end
    else
      return [ValidationUnexpected.new(
        path: path,
        expected: 'string',
        found: json_type_name(data),
      )]
    end
  end

  def to_s
    'URL'
  end
end

class PrimitiveTypeValidation < Validation
  attr_reader :type

  def validate(path, data)
    if @type === data
      return []
    else
      return [ValidationUnexpected.new(
        path: path,
        expected: @type.to_s,
        found: JsonType.new_from_value(data).to_s,
      )]
    end
  end

  def to_s
    @type.to_s
  end
end

class PrimitiveValueValidation < Validation
  attr_reader :value

  def validate(path, data)
    if JsonType.new_from_value(@value) === data
      if data == @value
        return []
      else
        return [ValidationUnexpected.new(path: path, expected: to_s, found: data.inspect)]
      end
    else
      return [ValidationUnexpected.new(
        path: path,
        expected: json_type_name(@value),
        found: JsonType.new_from_value(data).to_s,
      )]
    end
  end

  def to_s
    case @value
    when nil
      'null'
    else
      @value.inspect
    end
  end
end

class AnythingValidation < Validation
  def validate(path, data)
    return []
  end

  def to_s
    '__'
  end
end
