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
Puppet::Parser::Functions::newfunction(:get_secret, :type => :rvalue) do |vals|
  modulename = vals[0]
  identifier = vals[1]
  default    = vals[2]

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
  environment = get_secret_find_environment

  if environment == 'production'
    paths = [
    File.join(Puppet[:confdir], 'secret', modulename, "#{path}.yml"),
    File.join(Puppet[:confdir], 'secret', modulename, "#{path}.yaml"),
    ]
  else
    paths = []
    Puppet::Node::Environment.new(Puppet::Node::Environment.current).modulepath.each do |dir|
      paths.push("#{dir}/#{modulename}/secret_dev/#{path}.yml")
      paths.push("#{dir}/#{modulename}/secret_dev/#{path}.yaml")
    end
  end

  values = paths.map do |yaml_file|
    begin
      get_secret_get_value(yaml_file, modulename, key) if File.exists?(yaml_file)
    rescue
      next
    end
  end

  values = values.select { |val| !val.nil? }

  return values[0] if !values.empty?

  if !default
    raise Puppet::ParseError, "Unable to find secret value for module #{modulename} and key #{identifier}, tried #{paths.join(',')}"
  else
    debug("get_secret: Unable to find secret for #{identifier} in module #{modulename}; using default.")
    return default
  end
end

# these functions are used here and in get_var.rb
def get_secret_find_environment ()
  conf_file = File.join(Puppet[:confdir], 'master.yml')
  if (File.exists?(conf_file))
    conf = YAML.load_file(conf_file)
    if (conf['environment'])
      return conf['environment']
    end
  end

  return 'development'
end

def get_secret_get_value (yaml_file, modulename, identifier)
    if File.exists?(yaml_file)
      begin
        value = get_secret_drill_down(YAML.load_file(yaml_file), identifier.split(/\./))
        if value
          return value
        else
          return nil
        end
      rescue Puppet::ParseError => e
        raise e
      rescue Exception => e
        raise Puppet::ParseError, "Unable to parse secret yml file for module #{modulename}, tried #{yaml_file}: #{e}"
      end
    else
      return nil
    end
end

def get_secret_drill_down (data, ids)
  return nil unless data && ids.length > 0

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
      return data.keys.sort
    else
      return nil unless data.has_key?(id)
      return data[id]
    end
  else
    get_secret_drill_down(data[id], ids)
  end
end
