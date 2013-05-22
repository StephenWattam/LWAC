LWAC Concepts
=============
This document describes the format and purpose of the corpus around which LWAC is based, and serves to describe how one would go about operationalising the data therein.


Overview
--------
LWAC is based around a central longitudinal corpus, stored in an arbitrary directory (as defined in the server config) in a serialised object format (JSON, YAML, or ruby's native binary format).  This means the process of sampling is thus:

 1. Define a population of links
 2. Sample them with as small a time differential as possible
 3. Wait until the next sample time
 4. go to 2

A `link` without web data attached is known as a `datapoint` in this documentation.  A `sample` is one cross-sectional attempt to download all links.

Theoretically, this forms three levels at which we may access the data:

 1. Server level, describing the whole sample (all links, samples, and datapoints, a conventional longitudinal sample);
 2. Sample level, describing one attempt to download links (a conventional cross-sectional sample containing many datapoints);
 3. Datapoint level, describing one attempt to download a single link.

Simply, a server has many samples, each of which has many datapoints.  Samples are temporally homogenous to the greatest extent possible, and datapoints refer to the same URI (for their id).  Since the cumulative time taken to download each sample applies some drift, links are downloaded as intensively as possible.

The corpus, as stored on disk, consists of two types of storage:

 1. Metadata, stored in an SQLite database, which contains a table simply listing the links along with a unique ID.
 2. Corpus data, stored in a flatfile structure as serialised ruby DataPoint objects.

The format of the corpus is described in greater detail in the rest of this document.


The Corpus
----------

### Structure
The corpus itself is structured as a root directory, containing a specific structure:

    root/
    root/database.db
    root/state
    root/files/sample_id/sample
    root/files/sample_id/1/2/3/456


The corpus includes:

 * The metadata database (if using SQLite3)
 * The state of the current sample.  This is stored as a serialised ruby object so that a sample may be resumed later if the server is stopped.
 * A list of sample ID folders containing:
   * A file describing the properties of this sample as a serialised ruby Sample object
   * A structure of directories describing link IDs, each of which has up to N files within it (as defined in the server config).  This structure uses the first characters of the ID to nest directories in order to avoid filesystem limits on inode size and speed up random access, i.e.:
      0/1/1
      0/1/2
      0/1/3
      0/2/1
      0/2/2
      0/2/3
      etc.


### File Formats
Each of the files within a corpus, with the exception of the metadata database, is a serialised ruby object, as defined in `/lib/shared/data_types.rb`.  These objects are serialised using one of three formats:
 
 * `:marshal` --- Ruby's native binary format is very fast but cannot realistically be read from other languages
 * `:json` --- JSON is widely used but slow
 * `:yaml` --- YAML is also readable by other languages, but is slow (around 60 times slower than `:marshal`)

Note that a corpus written using one serialisation system will be unreadable by a server using another.  I highly recommend using `:marshal` and using the export tool to extract your data into a more workable format later.

