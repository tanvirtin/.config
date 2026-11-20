local treesitter = {}

function treesitter.language_of(filetype)
  return vim.treesitter.language.get_lang(filetype)
end

function treesitter.add_language(lang)
  return vim.treesitter.language.add(lang)
end

function treesitter.register_language(lang, label)
  vim.treesitter.language.register(lang, label)
end

function treesitter.parse_query(lang, source)
  return vim.treesitter.query.parse(lang, source)
end

function treesitter.query(lang, name)
  return vim.treesitter.query.get(lang, name)
end

function treesitter.query_files(lang, name)
  return vim.treesitter.query.get_files(lang, name)
end

function treesitter.string_parser(text, lang, opts)
  return vim.treesitter.get_string_parser(text, lang, opts)
end

function treesitter.range(node, text, metadata)
  return vim.treesitter.get_range(node, text, metadata)
end

function treesitter.node_text(node, text)
  return vim.treesitter.get_node_text(node, text)
end

return treesitter
