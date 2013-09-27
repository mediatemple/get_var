# Copyright (c) 2010 (mt) Media Temple Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
Puppet::Parser::Functions::newfunction(:get_var, :type => :rvalue) do |vals|
  modulename, identifier, default = vals

  # Make sure we know how many args were passed.
  argc = vals.length
  if( argc < 2 or argc > 3 )
    raise Puppet::ParseError, "get_var requires 2 or 3 arguments, you provided #{argc}."
  end

  # identifier can be a path and key delimited by a colon
  # the default path is 'main'.  examples:
  #  foo/bar:baz - looks in foo/bar.yml for key baz
  #  main:baz    - looks in main.yml for key baz
  #  baz         - looks in main.yml for key baz
  path, key = identifier.split(/:/)
  if key.nil?
    key = path
    path = 'main'
  end

  # check $confdir/master.yml to see what environment we're in
  Puppet::Parser::Functions.function('get_var_environment')
  environment = function_get_var_environment()

  if environment == 'production'
    var_path = 'var'
  else
    var_path = 'var_dev'
  end

  # look for the module in each directory in modulepath
  paths = []
  Puppet::Node::Environment.new(Puppet::Node::Environment.current).modulepath.each do |dir|
    paths.push("#{dir}/#{modulename}/#{var_path}/#{path}.yml")
    paths.push("#{dir}/#{modulename}/#{var_path}/#{path}.yaml")
  end

  if environment == 'development'
    paths.unshift(File.join(Puppet[:confdir], 'var_dev', modulename, "#{path}.yml"))
    paths.unshift(File.join(Puppet[:confdir], 'var_dev', modulename, "#{path}.yaml"))
  end

  values, found_key = GETVAR_NOTFOUND
  paths.map do |yaml_file|
    begin
      values, found_key = get_var_get_value(yaml_file, modulename, key) if File.exists?(yaml_file)
      if found_key
        break
      end
    rescue
      next
    end
  end

  if found_key
    return values
  end

  if argc < 3
    raise Puppet::ParseError, "Unable to find var for #{identifier} in module #{modulename}"
  else
    debug("get_var: Unable to find var for #{identifier} in module #{modulename}; using default.")
    return default
  end
end

GETVAR_NOTFOUND = [ nil, false ]

def get_var_get_value (yaml_file, modulename, identifier)
  if File.exists?(yaml_file)
    begin
      return get_var_drill_down(YAML.load_file(yaml_file), identifier.split(/\./))
    rescue Puppet::ParseError => e
      raise e
    rescue Exception => e
      raise Puppet::ParseError, "Unable to parse yml file for module #{modulename}, tried #{yaml_file}: #{e}"
    end
  else
    return GETVAR_NOTFOUND
  end
end

# Look for keys containing .'s first, then fall back. Returns a 2 element
# array where the first element is the derived value and the second element
# is true or false indicating if the value was found.  This allows as to
# distinguish between "not found" and "found, but false".
def get_var_drill_down (data, ids)
  return GETVAR_NOTFOUND unless data && ids.length > 0

  id = ""
  (ids.length - 1).downto(0) do |i|
    id = ids[0..i].join(".");

    if data.has_key?(id) || i == 0
      if i < ids.length - 1
        ids = ids[i + 1 .. ids.length - 1]
      else
        ids = []
      end
      break
    end
  end

  if (ids.length <= 0)
    if (id == 'keys')
      return [ data.keys.sort, true ]
    else
      if( data.has_key?(id) )
        return [ data[id], true ]
      else
        return GETVAR_NOTFOUND
      end
    end
  else
    return get_var_drill_down(data[id], ids)
  end
end
