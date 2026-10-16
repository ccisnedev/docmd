library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes the cover filter into [dir] and returns it. pandoc runs it through
/// its own Lua, so it adds no tool to install (ADR 0003).
File writeCoverFilter(Directory dir) =>
    File(p.join(dir.path, 'docmd-cover.lua'))
      ..writeAsStringSync(coverFilterLua);

/// Builds a cover page from the front matter's `cover:` block, the same
/// content in every format:
///
/// ```yaml
/// cover:
///   logo: assets/logo.png        # optional; logo-width defaults to 8cm
///   header: School of Engineering # one line or a list, under the logo
///   kind: Final report            # above the title, in capitals
///   title: …                      # defaults to the document title
///   subtitle: …
///   fields:                       # label: value rows, in this order
///     - Course: Discrete Mathematics
///   people:                       # a table: header row, then one row each
///     columns: [Student, Code]
///     rows:
///       - [Ana Pérez, U2025001]
///   footer: Lima, 2026            # one line or a list, at the bottom
///   colors: {accent: "#B91C1C", primary: "#1F2937"}
/// ```
///
/// The cover carries the title, so pandoc's own title block (title, subtitle,
/// author, date) is dropped instead of printing it a second time. In docx the
/// text is written as OpenXML runs and the logo sits in pandoc's Title style,
/// the one built-in paragraph style that is centered; a page break ends the
/// cover. In Typst the cover is a page of its own without a number, and the
/// body starts counting at 1.
const String coverFilterLua = r'''
local stringify = pandoc.utils.stringify
local upper = pandoc.text.upper

local function lines(value)
  if value == nil then return pandoc.List {} end
  if pandoc.utils.type(value) == 'List' then
    return pandoc.List(value):map(stringify)
  end
  return pandoc.List { stringify(value) }
end

local function text(value)
  if value == nil then return nil end
  local s = stringify(value)
  if s == '' then return nil end
  return s
end

local function color(value, default)
  local s = (text(value) or default):gsub('^#', '')
  return s:upper()
end

-- The cover as plain data, read once from the metadata.
local function read(meta)
  local c = meta.cover
  local colors = c.colors or {}
  local cover = {
    logo = text(c.logo),
    logo_width = text(c['logo-width']) or '8cm',
    header = lines(c.header),
    kind = text(c.kind),
    title = text(c.title) or text(meta.title),
    subtitle = text(c.subtitle) or text(meta.subtitle),
    fields = {},
    columns = {},
    rows = {},
    footer = lines(c.footer),
    accent = color(colors.accent, 'B91C1C'),
    primary = color(colors.primary, '1F2937'),
    muted = '5A6572',
  }
  for _, field in ipairs(c.fields or {}) do
    for label, value in pairs(field) do
      table.insert(cover.fields, { label = upper(label), value = stringify(value) })
    end
  end
  if c.people then
    cover.columns = lines(c.people.columns):map(upper)
    for _, row in ipairs(c.people.rows or {}) do
      table.insert(cover.rows, lines(row))
    end
  end
  return cover
end

-- OpenXML -------------------------------------------------------------------

local function xml(s)
  return (s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

-- A run: size in points, then optional bold, italic and color.
local function run(s, size, opts)
  opts = opts or {}
  return '<w:r><w:rPr>'
    .. (opts.bold and '<w:b/>' or '')
    .. (opts.italic and '<w:i/>' or '')
    .. '<w:color w:val="' .. (opts.color or '000000') .. '"/>'
    .. '<w:sz w:val="' .. math.floor(size * 2) .. '"/>'
    .. '</w:rPr><w:t xml:space="preserve">' .. xml(s) .. '</w:t></w:r>'
end

-- A centered paragraph; before and after in points.
local function para(runs, before, after, extra)
  return '<w:p><w:pPr>' .. (extra or '')
    .. '<w:spacing w:before="' .. math.floor((before or 0) * 20)
    .. '" w:after="' .. math.floor((after or 6) * 20) .. '"/>'
    .. '<w:jc w:val="center"/></w:pPr>' .. runs .. '</w:p>'
end

local function cell(runs, left)
  return '<w:tc><w:p><w:pPr><w:spacing w:before="80" w:after="80"/>'
    .. '<w:jc w:val="' .. (left and 'left' or 'center') .. '"/></w:pPr>'
    .. runs .. '</w:p></w:tc>'
end

local function border(side, size, hex)
  return '<w:' .. side .. ' w:val="single" w:sz="' .. size .. '" w:space="0" w:color="'
    .. hex .. '"/>'
end

-- The people table: a rule above and below, a thin one under the header.
local function people(cover)
  local head = {}
  for k, column in ipairs(cover.columns) do
    table.insert(head, cell(run(column, 9, { bold = true, color = cover.accent }), k == 1))
  end
  local rows = { '<w:tr>' .. table.concat(head)
    :gsub('<w:tc>', '<w:tc><w:tcPr><w:tcBorders>' .. border('bottom', 4, 'D1D5DB')
      .. '</w:tcBorders></w:tcPr>') .. '</w:tr>' }
  for _, row in ipairs(cover.rows) do
    local cells = {}
    for k = 1, #cover.columns do
      local value = row[k] or ''
      if k == 1 then
        table.insert(cells, cell(run(value, 12.5, { bold = true, color = cover.primary }), true))
      else
        table.insert(cells, cell(run(value, 12), false))
      end
    end
    table.insert(rows, '<w:tr>' .. table.concat(cells) .. '</w:tr>')
  end
  return '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:jc w:val="center"/>'
    .. '<w:tblBorders>' .. border('top', 6, cover.primary)
    .. border('bottom', 6, cover.primary) .. '</w:tblBorders></w:tblPr>'
    .. '<w:tblGrid>' .. ('<w:gridCol w:w="4400"/>')
    .. ('<w:gridCol w:w="2200"/>'):rep(#cover.columns - 1) .. '</w:tblGrid>'
    .. table.concat(rows) .. '</w:tbl>'
end

local function docx(cover)
  local blocks = pandoc.Blocks {}
  if cover.logo then
    blocks:insert(pandoc.Div(
      { pandoc.Para { pandoc.Image({}, cover.logo, '', { width = cover.logo_width }) } },
      { ['custom-style'] = 'Title' }))
  end
  local out = {}
  for _, line in ipairs(cover.header) do
    table.insert(out, para(run(line, 10.5, { color = cover.muted }), 0, 2))
  end
  table.insert(out, para('', 0, 0,
    '<w:pBdr><w:bottom w:val="single" w:sz="16" w:space="1" w:color="'
      .. cover.accent .. '"/></w:pBdr>'))
  if cover.kind then
    table.insert(out, para(run(upper(cover.kind), 11,
      { bold = true, color = cover.accent }), 90, 8))
  end
  if cover.title then
    table.insert(out, para(run(cover.title, 25,
      { bold = true, color = cover.primary }), cover.kind and 0 or 90, 10))
  end
  if cover.subtitle then
    table.insert(out, para(run(cover.subtitle, 12.5,
      { italic = true, color = cover.muted }), 0, 10))
  end
  for i, field in ipairs(cover.fields) do
    table.insert(out, para(
      run(field.label, 9, { bold = true, color = cover.accent })
        .. run('   ', 9) .. run(field.value, 12),
      i == 1 and 70 or 0, 8))
  end
  if #cover.columns > 0 then
    table.insert(out, para('', 10, 0))
    table.insert(out, people(cover))
  end
  for i, line in ipairs(cover.footer) do
    table.insert(out, para(run(line, 10.5, { color = cover.muted }),
      i == 1 and 90 or 0, 2))
  end
  table.insert(out, '<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
  blocks:insert(pandoc.RawBlock('openxml', table.concat(out, '\n')))
  return blocks
end

-- Typst ---------------------------------------------------------------------

local function str(s)
  return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

local function rgb(hex)
  return 'rgb("#' .. hex .. '")'
end

local function typst(cover)
  local accent, primary, muted = rgb(cover.accent), rgb(cover.primary), rgb(cover.muted)
  local open = { '#page(numbering: none, header: none, footer: none)[',
    '#set align(center)',
    '#set par(justify: false, first-line-indent: 0pt)' }
  local out = {}
  for _, line in ipairs(cover.header) do
    table.insert(out, '#v(4pt, weak: true)')
    table.insert(out, '#text(size: 10.5pt, fill: ' .. muted .. ', ' .. str(line) .. ')')
  end
  table.insert(out, '#v(8pt, weak: true)')
  table.insert(out, '#line(length: 100%, stroke: 2pt + ' .. accent .. ')')
  table.insert(out, '#v(1.4fr)')
  if cover.kind then
    table.insert(out, '#text(size: 11pt, weight: "bold", fill: ' .. accent
      .. ', tracking: 0.8pt, ' .. str(upper(cover.kind)) .. ')')
    table.insert(out, '#v(8pt, weak: true)')
  end
  if cover.title then
    table.insert(out, '#text(size: 25pt, weight: "bold", fill: ' .. primary
      .. ', ' .. str(cover.title) .. ')')
  end
  if cover.subtitle then
    table.insert(out, '#v(10pt, weak: true)')
    table.insert(out, '#text(size: 12.5pt, style: "italic", fill: ' .. muted
      .. ', ' .. str(cover.subtitle) .. ')')
  end
  table.insert(out, '#v(1.3fr)')
  if #cover.fields > 0 then
    local cells = {}
    for _, field in ipairs(cover.fields) do
      table.insert(cells, 'text(size: 9pt, weight: "bold", fill: ' .. accent
        .. ', tracking: 0.5pt, ' .. str(field.label) .. ')')
      table.insert(cells, 'text(size: 12pt, ' .. str(field.value) .. ')')
    end
    table.insert(out, '#grid(columns: (3.2cm, 1fr), column-gutter: 16pt, '
      .. 'row-gutter: 12pt, align: (right + horizon, left + horizon), '
      .. table.concat(cells, ', ') .. ')')
  end
  if #cover.columns > 0 then
    local head, body = {}, {}
    for _, column in ipairs(cover.columns) do
      table.insert(head, 'text(size: 9pt, weight: "bold", fill: ' .. accent
        .. ', tracking: 0.5pt, ' .. str(column) .. ')')
    end
    for _, row in ipairs(cover.rows) do
      for k = 1, #cover.columns do
        local cell = row[k] or ''
        if k == 1 then
          table.insert(body, 'text(size: 12.5pt, weight: "bold", fill: '
            .. primary .. ', ' .. str(cell) .. ')')
        else
          table.insert(body, 'text(size: 12pt, ' .. str(cell) .. ')')
        end
      end
    end
    table.insert(out, '#v(20pt)')
    table.insert(out, '#table(columns: (1fr,) + (auto,) * '
      .. (#cover.columns - 1) .. ', align: (left + horizon,) + (center + horizon,) * '
      .. (#cover.columns - 1) .. ', stroke: none, inset: (x: 10pt, y: 7pt), '
      .. 'table.hline(stroke: 0.8pt + ' .. primary .. '), '
      .. 'table.header(' .. table.concat(head, ', ') .. '), '
      .. 'table.hline(stroke: 0.6pt + ' .. rgb('D1D5DB') .. '), '
      .. table.concat(body, ', ') .. ', '
      .. 'table.hline(stroke: 0.8pt + ' .. primary .. '))')
  end
  table.insert(out, '#v(1fr)')
  if #cover.footer > 0 then
    table.insert(out, '#line(length: 45%, stroke: 0.6pt + ' .. rgb('D1D5DB') .. ')')
    table.insert(out, '#v(8pt, weak: true)')
    local footer = {}
    for _, line in ipairs(cover.footer) do
      table.insert(footer, '#text(size: 10.5pt, fill: ' .. muted .. ', ' .. str(line) .. ')')
    end
    table.insert(out, table.concat(footer, ' \\\n'))
  end
  table.insert(out, ']')
  table.insert(out, '#counter(page).update(1)')

  local blocks = pandoc.Blocks { pandoc.RawBlock('typst', table.concat(open, '\n')) }
  if cover.logo then
    blocks:insert(pandoc.Para {
      pandoc.Image({}, cover.logo, '', { width = cover.logo_width }) })
  end
  blocks:insert(pandoc.RawBlock('typst', table.concat(out, '\n')))
  return blocks
end

function Pandoc(doc)
  if doc.meta.cover == nil then
    return nil
  end
  local cover = read(doc.meta)
  local blocks
  if FORMAT == 'docx' then
    blocks = docx(cover)
  elseif FORMAT == 'typst' then
    blocks = typst(cover)
  else
    return nil
  end
  doc.blocks = blocks .. doc.blocks
  -- The cover holds the title; pandoc's title block would repeat it.
  doc.meta.title = nil
  doc.meta.subtitle = nil
  doc.meta.author = nil
  doc.meta.date = nil
  return doc
end
''';
