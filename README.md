# JSON Patterns

The JSON Patterns Ruby Gem is a domain-specific language (DSL) library for validating
the structure of JSON documents, using patterns that resemble JSON. Just as regexps
look a lot like a string, with special symbols to match patterns, a JSON pattern looks
like a JSON value, with special keywords to allow for abstract pattern matching.

It supports the use of alternate object patterns, which can be distinguished by a tag.
This allows for a JSON structure to mimic subtyping.

## Contents

This gem contains:

* A family of classes descending from Pattern that represents JSON patterns.
* A series of helper functions that provide special keywords to make pattern
  creation easy.
* A family of classes descending from `Validation` or `ObjectMemberValidation`,
  that do the work of validating your JSON structures.

## Installation

    gem install json-patterns

You will also need a JSON parser, such as [yajl-ruby][]. This gem works only in
Ruby 1.9 and higher.

[yajl-ruby]: https://github.com/brianmario/yajl-ruby

## Usage

1. `require 'json_patterns'`
2. Create a pattern.
3. Call `Validation.new_from_pattern` on the pattern to generate a `Validation`.
4. Obtain a JSON string, and use a JSON parser such as [yajl-ruby][] to parse it
   into a nested Ruby data structure.
5. Call the `validate_from_root` method on the `Validation` object, passing it
   the parsed JSON. You'll get an array of `ValidationFailure` objects. If it's
   empty, the validation was successful.

Example:

    require 'yajl'
    require 'json_patterns'

    pattern = { users: array_of({ id: Integer, name: String }) }
    validation = Validation.new_from_pattern(pattern)

    json = File.new('users.json', 'r')
    parser = Yajl::Parser.new
    hash = parser.parse(json)

    errors = validation.validate(hash)
    print errors

## Pattern Syntax

The simplest patterns are JSON literals:

* A boolean value, e.g. `true`
* A number, e.g. `5` or `-3.26`
* A string, e.g. `"foo"`
* The Ruby value `nil` represents a JSON `null`

You can match values of a particular type, by using either a Ruby class or the JSON
name as a symbol:

* `Boolean` or `:boolean` matches a `true` or `false`
* `TrueClass` matches `true`, `FalseClass` matches `false`
* `String` or `:string` matches a string
* `Integer` or `:integer` matches an integer
* `Float`, `Numeric` or `:float` matches a floating-point number
* `NilClass` matches a JSON `null`
* `Array` or `:array` matches any array
* `Hash` or `:object` matches a JSON object

You can match some special kinds of strings, too:

* `Email` matches an email address
* `URL` matches an `http`, `https` or `ftp` URL
* A `Regexp` such as `/a.*b/` matches strings that match the `Regexp`

You can match arrays, but only when every element is expected to have a different value.
These are called *uniform arrays*.

    array_of(String)

will match a JSON array where all elements are expected to be a string.

You can match JSON objects using Ruby hashes. Please note the terminology differences:
**hashes** in Ruby are called **objects** in JSON. **Key-value pairs** in Ruby are called
**object members** in JSON, and Ruby's **keys** are called **names** in JSON. All class
names and error messages use the JSON terminology.

So, a hash:

    { id: Integer, name: String }

will match a JSON object with names `id` and `name`, with corresponding integer and string
values, respectively. For example,

    { "id": 5, "name": "Bob" }

Analogous to the ability to match uniform arrays, you can match *uniform objects.* These
are objects that may have an arbitrary number of names, but each value must match the
same pattern. For example,

    { many => String }

will match any object where all the values are strings. The `many` keyword is a special
helper function provided by the gem.

Optional names can be matched in an object using the `optional` keyword:

    { id: Integer, name: String, optional => { address: String } }

will match objects with an `id` and a `name`, and optionally an `address` with a string
value. If multiple members are listed in an `optional` clause, they must occur together.
So,

    { id: Integer, optional => { name: String, address: String } }

would match objects with an `id` only, or objects with names `id`, `name` and `address`,
but `name` cannot appear with out `address`, or vice versa.

### Alternate patterns (disjunctions)

It is possible to match one of a set of alternate patterns. There are two syntaxes for
this, depending on the context. If you are trying to match one of a set of values,
pass a list of patterns to the `one_of` function. E.g.,

    one_of('circle', 'square', 'triangle')

will match any of the three strings. Note that the values passed to `one_of` need not
all be of the same type.

In an object member context, use the keyword `one_of`, with an array value listing the
    { id: Integer, one_of => [ { name: String }, { age: Integer } ] }

This will match an object with an name `id` of type integer, and *either* the name
`name` with a string value, or the name `age` with an integer value. Once again,
the internal hashes may contain multiple keys. You can think of the curly braces
in this case as mere syntax: they delineate a pattern of object members, not a
nested object. You can think of the `one_of` keyword as removing the top level of
curly braces inside the array.

A common use case for alternate object patterns is to indicate different "types"
that can be considered subtypes of some base type. In Ruby, you might use subclasses
to represent alternate forms. For example, if you were representing HTML form
element tags, you might have a base `Tag` class, with subclasses such as
`InputTag`, `TextAreaTag`, or `SelectTag`.  Each of these would in turn have
different attributes, though they would share some attributes in common.

In JSON, you might represent an `<input>` tag with a pattern like this (deliberately
oversimplified):

    { tag: 'input', type: one_of('checkbox', 'text'), value: String }

and a `<textarea>` tag with a pattern like this:

    { tag: 'textarea', rows: Integer, cols: Integer }

To handle either type of tag, you could use a `one_of` pattern. To simplify the
code, we can use Ruby variables to hold on to each pattern:

    inputTag = { tag: 'input', type: one_of('checkbox', 'text'), value: String }
    textAreaTag = { tag: 'textarea', rows: Integer, cols: Integer }
    tag = one_of(inputTag, textAreaTag)

So one can think of `tag` as a base class, and `inputTag` and `textAreaTag` as
subclasses. They are distinguished by the value of the `tag` object member.

The Validation objects are smart enough to look at the first object members
(key-value pairs) of alternate patterns, and use them to distinguish the
appropriate case to follow. Please note that they must be distinguished by
the first name (key) or value encountered in the pattern. There is a deliberate
ordering to the object members in the patterns, but no ordering in the matched
JSON objects. If the cases are not distinguished by the first object member
of the pattern, a ValidationAmbiguity error will occur.

### Cyclic patterns

Sometimes it is desirable to match nested patterns that repeat. This can
be done using the `cyclic` function:

    cyclic { |person| { name: String, email: Email, friends: array_of(person) } }

This matches an object with three names: `name`, `email` and `friends`, where
`friends` points to an array of objects with `name`, `email`, and `friends`,
and so on. If you create a cyclic structure, you are responsible for ensuring that
it is *well-founded,* that is, it should not require an infinite-sized JSON
structure, as all JSON structures are finite. This pattern is well-founded,
because at any level in the hierarchy, the `friends` list may be empty.

Note that we are making use of Ruby's block syntax to create a local variable
`person` which can be used to refer to the top level of the cyclic structure.
Here is another well-founded example:

    tree = cyclic { |tree| one_of(Integer, { left: tree, right: tree }) }

This time, we show storing the result in a variable. Please note that due to
Ruby scoping rules, the `tree` variable on the outside is distinct from
the other `tree` variables inside the call to `cyclic`, which all refer
to the same thing. This pattern would match JSON such as:

    { "left": 4, "right": { "left": 2, "right": 5 } }

### The members keyword

You may have noticed that, whenever we use a special keyword within a hash,
the value, that is represented as a hash, is treated as a list of object
members, rather than as an object. There is a special keyword called
`members`, which does nothing but apply this transformation. It is useful
if you have a pattern that represents an object, and want to flatten
it into a list of object members.

For example, if you have an object pattern:

    address = { street: String, city: String }

You could use it as a nested object:

    user = { name: String, address: address }

which would match JSON like this:

    { "name": "Bob", "address": { "street": "10 Forbes Ave", "city": "New York" } }

Using the `members` keyword, you can flatten the pattern:

    user = { name: String, members => address }

This will match JSON such as:

    { "name": "Bob", "street": "10 Forbes Ave", "city": "New York" }

Note that the same pattern can be used in both ways, in different places. In
addition, the same flattening occurs if a pattern is used along with the
`one_of` or `optional` keywords.

## Errors

Errors are descended from the class `ValidationError`, which consists of subclasses
`ValidationUnexpected` and `ValidationAmbiguity`. Each of them has a `path`
attribute, which is an array containing the path through the JSON where the error
was found. Each element in the array is either a string (object name) or integer
(array index).

A `ValidationUnexpected` has `found` and `expected` attributes, describing what was
found and what was expected, respectively. The description is minimal for indicating
what went wrong. For example, if a string was expected but an array was found, then
`found` would indicate "array", rather than representing the entire contents of the
array. If alternate values were expected, they will be listed in an array, e.g.:

    expected: ["square", "circle", "triangle"]
    found: "dodecahedron"

If a certain name was expected, but not found, all the names found in the object will
be listed. For example,

    expected: 'name: "street"'
    found: 'names: "name", "city"'

A `ValidationAmbiguity` has `found` and `overlapping_patterns` attributes. The
`found` attribute describes what was found, and `overlapping_patterns` is an array
of minimal textual descriptions of the alternate patterns that matched what was
found.

All errors have a `to_s` method for convenient textual representation.

== Questions and Answers

**Q:** Why only Ruby 1.9? Can you support 1.8?

**A:** There are several reasons for using Ruby 1.9, but the most important
one is that there is a guaranteed ordering of key-value pairs in hashes. This
is required for the patterns to be ordered. The JSON-like key syntax of following
the key with a colon instead of using a rocket is nice, too.

**Q:** I'd like to match arrays of a fixed length, with different patterns at each
index. Is that possible?

**A:** Not at the moment. I may add this in a future version. The syntax would
simply be the Ruby array syntax. I just haven't had a use for this yet.

**Q:** How about checking the length of a string?

**A:** You can use a Regexp. `/.{8,8}` will match 8-character strings.

**Q:** How about checking a numeric range?

**A:** Not possible in this version.

**Q:** I want to use arbitrary functions to validate values.

**A:** Not possible at the moment, but I might consider adding this. One thing
I don't like about it is that it's not serializable.

**Q:** Your `one_of` keyword is like an `or`. How about a sort of `and` operation
on patterns?

**A:** Yes, I'm considering creating an `all_of` for that. It's too bad you can't
overload the `&&` and `||` operators in Ruby.

**Q:** How about using regexes for keys?

**A:** This creates too much ambiguity. The number of cases that must be tried
is larger, and the error messages become more confusing. Better to be clear
with your structure definition.

Instead I have special cased the `/.*/` regex using the `many` keyword. With
this there is no ambiguity about which names should be matched. All are matched.

**Q:** What is this "name" thing? Do you mean keys?

**A:** See the [JSON specification](http://www.json.org/). They really do call them
object members, and name/value pairs. Just trying to stick with the spec. Sorry
for the confusion.

**Q:** But you can't do mutually recursive patterns with `cyclic`!

**A:** OK, smartypants. I didn't have a use for mutually recursive patterns.
But it is possible to write them, by manipulating the patterns after you
create them, to point at each other. The magic `cyclic` keyword isn't really
required. The Pattern -> Validation transformation preserves all sharing
and cyclic structures. Exercise left for the daring reader.

**Q:** If there's an ambiguity error, it can be hard to find where in the pattern
the problem is occuring.

**A:** At some point I may implement pattern paths. They won't be aware of the
Ruby variables you've used, but it could help.

## Acknowledgements

Thanks to [Janrain](http://janrain.com), my employer, for permitting me to open source
this code under my own name.
