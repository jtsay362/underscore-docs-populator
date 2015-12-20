require 'json'
require 'uri'
require 'net/http'
require 'fileutils'
require 'nokogiri'

UNDERSCORE_DOCS_URL = 'http://underscorejs.org/'
DOWNLOAD_DIR = './downloaded'
DOWNLOAD_FILENAME = "#{DOWNLOAD_DIR}/underscorejs.html"

class UnderscorePopulator
  def initialize(output_path)
    @output_path = output_path
  end

  def download
    puts "Starting download ..."

    FileUtils.mkpath(DOWNLOAD_DIR)
    uri = URI.parse(UNDERSCORE_DOCS_URL)
    response = Net::HTTP.get_response(uri)
    File.write(DOWNLOAD_FILENAME, response.body)


    puts "Done downloading!"
  end

  def populate
    File.open(@output_path, 'w:UTF-8') do |out|
      out.write <<-eos
{
  "metadata" : {
    "settings" : {
      "analysis": {
        "char_filter" : {
          "no_special" : {
            "type" : "mapping",
            "mappings" : ["_=>", ".=>"]
          }
        },
        "analyzer" : {
          "lower_keyword" : {
            "type" : "custom",
            "tokenizer": "keyword",
            "filter" : ["lowercase"],
            "char_filter" : ["no_special"]
          }
        }
      }
    },
    "mapping" : {
      "_all" : {
        "enabled" : false
      },
      "properties" : {
        "name" : {
          "type" : "string",
          "analyzer" : "lower_keyword"
        },
        "syntax" : {
          "type" : "string",
          "index" : "no"
        },
        "aliases" : {
          "type" : "string",
          "analyzer" : "lower_keyword"
        },
        "descriptionHtml" : {
          "type" : "string",
          "index" : "no"
        },
        "exampleUsage" : {
          "type" : "string",
          "index" : "no"
        },
        "suggest" : {
          "type" : "completion",
          "analyzer" : "lower_keyword"
        }
      }
    }
  },
  "updates" :
    eos
      function_docs = parse_function_docs()

      puts "Found #{function_docs.length} functions."

      out.write(function_docs.to_json)
      out.write("\n}")
    end
  end

  def parse_function_docs()
    source_doc = Nokogiri::HTML(File.read(DOWNLOAD_FILENAME))

    source_doc.css('#documentation>p').map { |p|
      header = p.css('.header')
      name = header.text.strip

      aliases = p.css('.alias b').text.strip.split(/\s*,\s*/)

      if aliases.length == 1 && aliases[0].strip.empty?
        aliases = []
      end

      code_blocks = p.css('code')

      first_br = p.css('br').first
      description_html = nil

      if first_br
        description_html = ''

        node = first_br.next_sibling

        while node
          description_html += node.to_html
          node = node.next_sibling
        end
      end

      syntax_node = code_blocks.first
      syntax = ''

      if syntax_node
        syntax = syntax_node.text.strip
      end

      example_usage = nil

      next_node = p.next_element

      while next_node
        tag = next_node.name

        if tag == 'pre'
          example_usage = next_node.text.strip
          next_node = nil
        elsif tag == 'p'
          description_html = (description_html || '') + next_node.to_html
          if next_node.attr('id') # start of next function
            next_node = nil
          else
            next_node = next_node.next_element
          end
        else
          next_node = nil
        end
      end

      unless name.empty? || syntax.empty?
        doc = {
          name: name,
          syntax: syntax,
          aliases: aliases,
          descriptionHtml: description_html.strip,
          exampleUsage: example_usage,
          suggest: {
            input: [name] + aliases,
            output: name
          }
        }
        doc
      else
        nil
      end
    }.compact
  end
end

output_filename = 'underscore-docs.json'

download = false

ARGV.each do |arg|
  if arg == '-d'
    download = true
  else
    output_filename = arg
  end
end

populator = UnderscorePopulator.new(output_filename)

if download
  populator.download()
end

populator.populate()
system("bzip2 -kf #{output_filename}")