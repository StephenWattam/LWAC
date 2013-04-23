Reading Configuration Documentation
===================================
Configuration files in LWAC are valid YAML files, and typically follow a hash structure.  As such they resemble large trees, with occasional lists and many small textual elements.

A first place to look when interpeting these will be [the YAML overview at Wikipedia](http://en.wikipedia.org/wiki/YAML), which will help familiarise you with the format.  The rest of this document is about how I refer to keys and values in this documentation.

Keys
----
YAML keys will be specified as paths from root, loosely following XPATH notation: `/key1/key2/key3` will denote

    ---
    :key1:
      :key2:
         :key3: value


Where YAML files contain lists, aspect specifiers will be used in a similar manner to C-like languages (0-base), i.e. `/key1/key2[2]` refers to `orange`:

    ---
    :key1:
      :key2:
        - apple
        - banana
        - orange

Where YAML keys contain hashes, that must be retained as simple key-value pairs (i.e. for SQLite pragma settings), curly braces will be used as aspect specifiers, i.e. `/key1/key2{orange}` will refer to `bob`:

    ---
    :key1:
      :key2:
        apple: adolf
        banana: martin
        orange: bob


Symbols and Data Formats
------------------------
Most, though not all, keys in LWAC configuration files are symbols, and thus are prefixed with a colon (:).  Those that are specifically not symbols are noted as such in the text, as it is normally relevant to their use.

Booleans and other binary options are also noted in the text, and it's worth noting that ruby considers `nil` to be false in boolean tests.
