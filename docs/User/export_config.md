Export Tool Configuration
=========================
The export tool accesses the server's corpus and exports it according to a series of complex policies.  As such its configuration file is very open-ended and may contain significant portions of ruby code, however, every effort has been made to make simple things simple.  

Data Access
-----------
Many of the features of the export tool require an understanding of how data is structured within the tool.  Data access is structured as a large tree, augmented and constructed at each level as the data is exported.  Variables are accessed on the tree by using dot notation, as with any member variables in ruby (i.e. `data.sample.id` will get the ID of the current sample).

Note that the export tool will only allow exporting of complete samples, i.e. those where all the links have been downloaded and the sample closed.

The hierachy is currently as below:

 * `data` --- Root object, containing each level as a member
   * `.server` --- Server-level variables, including server state
     * `.links` --- A list of links available to download
     * `.complete_sample_count` --- How many samples have completely downloaded and have available data?
     * `.complete_samples` --- A list containing the IDs of all the complete samples
     * `.next_sample_date` --- The date of the next sample due
     * `.current_sample_id` --- The ID of the current sample (the next, incomplete, one)
     * `.version` --- The version of the server used to write the corpus
     * `.config` --- The server configuration, as a hash
   * `.sample` --- Sample-level variables
     * `.id` --- The ID of the sample
     * `.start_time` --- The time the sample started acquiring data
     * `.end_time` --- The time the sample stopped and checked in the final link
     * `.start_time_s` --- The start time in seconds from the UNIX epoch
     * `.end_time_s` --- The end time in seconds from the UNIX epoch
     * `.complete` --- Boolean. Is the sample complete?
     * `.open` --- Boolean.  Is the sample open?
     * `.size` --- How many links are covered by the sample?
     * `.duration` --- How long did the sample take, in seconds? (`end_time_s` - `start_time_s`)
     * `.num_pending_links` --- How many links are still waiting to be completed?
     * `.pending_links` --- A list of links still waiting to be downloaded.
     * `.last_contiguous_id` --- The last id read from the database.  Links yet to be completed equal (sample.size - last_contiguous_id) union (pending_links)
     * `.size_on_disk` --- The approximate filesize on disk, in bytes, of all data in this sample
     * `.dir` --- The directory for that sample, relative to the current working directory
     * `.path` --- The filepath of the sample information file, relative to the current working directory
   * `.datapoint` --- Datapoint-level variables
     * `.id` --- The ID of the datapoint/link
     * `.uri` --- The URI requested to acquire the data
     * `.path` --- The full filepath of the datapoint file, relative to the current working directory
     * `.dir` --- The directory in which the datapoint resides, relative to the current working directory
     * `.client_id` --- The ID of the client that did the work
     * `.error` --- Any errors reported during download
     * `.headers` --- A hash containing the HTTP headers
     * `.head` --- A string containing the HTTP headers
     * `.body` --- The body content of the HTTP response
     * `.response` --- The response object properties, as reported by cURL (Hash)
       * `.round_trip_time` --- The total time for the request
       * `.redirect_time` --- The time spend in redirects
       * `.dns_lookup_time` --- The time spend looking up DNS
       * `.effective_uri` --- The 'real' URI used, after redirects
       * `.code` --- The response code
       * `.download_speed` --- The download speed reported by cURL
       * `.downloaded_bytes` --- The number of bytes downloaded, as reported by cURL
       * `.encoding` --- The encoding, as reported by cURL.  Note that this seems unreliable
       * `.truncated` --- Boolean. `true` if the body was truncated due to the server's maximum filesize limit
       * `.dry_run` --- Boolean.  `true` if this datapoint was sampled as part of a dry run (no data will have been transferred to/from the web)
       * `.mime_allowed` --- Boolean. `false` if the MIME type policy on the server caused this document's body to be discarded, or `true` otherwise



Config
-------------
The export tool uses the server configuration to access a corpus, and loads it as if it were a server.

 * `server_config` --- The path to the server configuration file.

Output
------
Output is controlled using a filter/format system, which progresses through a series of expressions first to test for inclusion of data in the output set, and then to format it for presentation.  Currently the export tool only outputs CSV files.

 * `announce` --- How often to update the terminal with progress information
 * `filename` --- The filename to export data into.  Will be clobbered rather than appended to.
 * `headers` --- Boolean.  Should the script output a header line at the top of the CSV?
 * `level` --- What level to export at.  Possible values are `:server`, `:sample` or `:datapoint`.  This is partially used for optimisation---exporting datapoint-level variables with `level` set to `:server` will result in them all being nil.  See [concepts](concepts.html) for more information on what the levels correspond to within the LWAC system.

 * `filters[]` --- This is outlined in its own section below...
 * `format{}` --- This is *also* outlined in its own section below...



### Filtering
Filters are small scripts that, presented with data, return true to include a value in output, or false to discount it.  Filters may operate at any level to exclude a certain `:server`, `:sample`, or `:datapoint`, and are defined in one of these three lists.

 * `filters/server[]`, `filters/sample[]`, `filters/datapoint[]` --- Each entry in one of these lists should be an expression that evaluates to `true`/non-`nil` or `false`/`nil`.

Data access is governed by a 'data' object containing a hierachy of all available data at the given level.  See 'Data Access' above for more information on how to refer to specific variables.



### Formatting
Data, once selected, must be formatted for output.  This is generally complicated by the need to handle missing data, especially where data is acquired from the web and may be particularly messy.  Variables may be formatted for output using one of three structures, each defined by a hash.

 * `format/FIELD_NAME{}` --- Output the result of the hash contained in `FIELD_NAME` as `FIELD_NAME`.  The contents of the `FIELD_NAME` hash may be one of the formats detailed below

#### Simple Variable Formatting
This is the simplest way of output a value, and should work in most instances.  To use it, simply specify the variable name (the `data.` prefix is optional), for example:

    :format:
      :sample_id: sample.id
      :link_id: datapoint.id

This will output a CSV with two columns, `sample_id` and `link_id`.


#### Variable-and-condition 
This will output the contents of a given variable if and only if a condition is true, and may be used to ensure that certain values are reported as missing.  It is defined as a hash containing three properties:

 * `FIELD_NAME/var` --- The variable in question.  The preceeding `data.` may be omitted, as with simple variable formatting above.
 * `FIELD_NAME/condition` --- An expression that evaluates to true if the value is to be output.  The value in question will be called `x` in the expression.
 * `FIELD_NAME/missing` --- A value to output if the expression above evaluates to false.

For example:

    :format:
      :redirect_time:
        :var: datapoint.response.redirect_time
        :condition: "(x and x.to_f > 0)"
        :missing: ""

This ensures that the `redirect_time` field is only populated if it is non-`nil` and contains a value over zero.


#### Expression-based Formatting
The most powerful, and complex, form of formatting relies on a free-form ruby expression to return a value for output.  The expression in question is provided as a string, as with other expression objects, and may handle any variables within the export tool whilst processing.  There is only one entry in the hash required:

 * `FIELD_NAME/expr` --- The expression to be used.  *Must* return a value.

For example:

    :format:
      :okay_resp: 
        :expr: "data.datapoint.response.code.to_i == 200"
      :redirect_proportion:               # A long expression on multiple lines
        :expr: >
          r = data.datapoint.response
  
          if(r.redirect_time and r.redirect_time > 0) then
              return r.redirect_time.to_f / r.round_trip_time.to_f
          else
              return "NA"
          end

This example outputs two fields.  The former, `okay_resp`, outputs 'true' if the response code was 200.  The latter, which uses YAML's multi-line string syntax, computes the redirect time as a proportion of the total request time, as a measure of 'how redirected' something was, and returns "NA" if the times are unavailable.


Logging
-------
The logging system is the same for client, server, and export tools and shares a configuration with them.  For details, see [configuring logging](log_config.html)
