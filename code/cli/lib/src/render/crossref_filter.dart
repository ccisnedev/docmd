library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes the cross-reference filter into [dir] and returns it. pandoc runs it
/// through its own Lua, so it adds no tool to install (ADR 0003).
File writeCrossrefFilter(Directory dir) =>
    File(p.join(dir.path, 'docmd-crossref.lua'))
      ..writeAsStringSync(crossrefFilterLua);

/// Numbers figure and table captions ("Figura 1: …") and resolves `@fig:id` /
/// `@tbl:id` to the same numbers, in every output format.
///
/// The filter owns the numbering, so the docx and the pdf cannot disagree:
/// pandoc's docx writer numbers nothing, and Typst's own figure numbering is
/// turned off so it does not print a second "Figura 1:". It must run before
/// citeproc, which would otherwise read `@fig:id` as a missing citation; an
/// unknown reference becomes "??" (and a warning) instead of a link to a
/// missing label, which aborts a Typst render. For Typst it also lets a table
/// figure break across pages.
const String crossrefFilterLua = r'''
local words = {
  es = { fig = 'Figura', tbl = 'Tabla' },
  en = { fig = 'Figure', tbl = 'Table' },
}

local function label(word, n)
  return pandoc.Inlines { pandoc.Str(word), pandoc.Space(), pandoc.Str(tostring(n)) }
end

local function prefix(caption, word, n)
  local head = label(word, n) .. pandoc.Inlines { pandoc.Str(':'), pandoc.Space() }
  local long = caption.long
  local first = long[1]
  if first and (first.t == 'Plain' or first.t == 'Para') then
    first.content = head .. first.content
  end
  caption.long = long
  return caption
end

function Pandoc(doc)
  local lang = pandoc.utils.stringify(doc.meta.lang or ''):sub(1, 2):lower()
  local names = words[lang] or words.en
  local count = { fig = 0, tbl = 0 }
  local numbers = {}

  local function number(element, kind)
    if #element.caption.long == 0 then
      return nil
    end
    count[kind] = count[kind] + 1
    if element.identifier ~= '' then
      numbers[element.identifier] = { kind = kind, n = count[kind] }
    end
    element.caption = prefix(element.caption, names[kind], count[kind])
    return element
  end

  doc.blocks = doc.blocks:walk {
    traverse = 'topdown',
    Figure = function(figure) return number(figure, 'fig') end,
    Table = function(tbl) return number(tbl, 'tbl') end,
  }

  doc.blocks = doc.blocks:walk {
    Cite = function(cite)
      local id = cite.citations[1].id
      local kind = id:match('^(%a+):')
      if #cite.citations ~= 1 or (kind ~= 'fig' and kind ~= 'tbl') then
        return nil
      end
      local target = numbers[id]
      if target then
        return label(names[target.kind], target.n)
      end
      io.stderr:write('[docmd] unresolved reference: @' .. id .. '\n')
      return pandoc.Str('??')
    end,
  }

  if FORMAT == 'typst' then
    doc.blocks:insert(1, pandoc.RawBlock('typst', '#set figure(numbering: none)'))
    -- pandoc wraps a captioned table in a figure, and a Typst figure does
    -- not break: a long table would move whole to the next page.
    doc.blocks:insert(2, pandoc.RawBlock('typst',
      '#show figure.where(kind: table): set block(breakable: true)'))
  end
  return doc
end
''';
