htmlParser = require './htmlParser'

View = module.exports = ->
  self = this
  @_views = {}
  @_loadFuncs = ''
  
  # All automatically created ids start with an underscore
  @uniqueId = -> '_' + (self._idCount++).toString 36
  
  return

View:: =

  get: (view, obj) ->
    if view = @_views[view]
      if Array.isArray obj
        (view item for item in obj).join ''
      else view obj
    else ''

  preLoad: (fn) -> @_loadFuncs += "(#{fn})();"

  make: (name, template, data) ->
    if template.model || !~template.indexOf('{{')
      data = template
      simple = true
    else
      data = {}  if data is undefined
    
    before = data && data.Before
    after = data && data.After
    uniqueId = @uniqueId
    self = this

    render = ->
      render = if simple
          simpleView name, self
        else parse template, data, uniqueId, self
      render arguments...

    fn = if typeof data is 'function'
        -> render data arguments...
      else
        -> render data

    @_views[name] =
      if before
        if after then ->
          before()
          fn arguments...
          after()
        else ->
          before()
          fn arguments...
      else
        if after then ->
          fn arguments...
          after()
        else fn


View.htmlEscape = htmlEscape = (s) ->
  if `s == null` then '' else s.toString().replace /[&<>]/g, (s) ->
    switch s
      when '&' then '&amp;'
      when '<' then '&lt;'
      when '>' then '&gt;'
      else s

quoteAttr = (s) ->
  return '""' if `s == null` || s is ''
  s = s.toString().replace /"/g, '&quot;'
  if /[ =]/.test s then '"' + s + '"' else s

extractPlaceholder = (text) ->
  match = /^([^\{]*)(\{{2,3})([^\}]+)\}{2,3}(.*)$/.exec text
  return null unless match
  content = /^([#^//>]?) *([^\|]*)(?: *> *(.*))?$/.exec match[3]
  pre: match[1]
  escaped: match[2] == '{{'
  type: content[1]
  name: content[2]
  partial: content[3]
  post: match[4]

addNameToData = (data, name) ->
  data[name] = model: name  unless name of data

modelText = (view, name, escaped, quote) ->
  (data) ->
    datum = data[name]
    obj = if datum.model then view.model.get datum.model else datum
    text = if datum.view then view.get datum.view, obj else obj
    text = htmlEscape text  if escaped
    text = quoteAttr text  if quote
    return text

getElementParse = (view, events) ->
  input: (attr, attrs, name) ->
    return 'attr'  unless attr == 'value'
    if 'silent' of attrs
      delete attrs.silent
      method = 'prop'
      silent = 1
    else
      method = 'propPolite'
      silent = 0
    events.push (data) ->
      domArgs = ['set', data[name].model, attrs._id || attrs.id, 'prop', 'value', silent]
      domEvents = view.dom.events
      domEvents.bind 'keyup', domArgs
      domEvents.bind 'keydown', domArgs
    return method

parse = (template, data, uniqueId, view) ->
  stack = []
  events = []
  html = ['']
  htmlIndex = 0
  model = view.model

  elementParse = getElementParse view, events

  htmlParser.parse template,
    start: (tag, attrs) ->
      for key, value of attrs
        if match = extractPlaceholder value
          {name, escaped} = match
          addNameToData data, name
          if attrs.id is undefined
            attrs.id = -> attrs._id = uniqueId()
          method = if tag of elementParse then elementParse[tag] key, attrs, name else 'attr'
          events.push (data) ->
            path = data[name].model
            model.__events.bind path, [attrs._id || attrs.id, method, key]  if path
          attrs[key] = modelText view, name, escaped, true
      stack.push ['start', tag, attrs]

    chars: chars = (text) ->
      if match = extractPlaceholder text
        {name, escaped, pre, post, type, partial} = match
        addNameToData data, name
        stack.push ['chars', pre]  if pre
        if wrap = pre || post || stack.length is 0
          stack.push ['start', 'span', {}]
        text = modelText view, name, escaped
        last = stack[stack.length - 1]
        if last[0] == 'start'
          attrs = last[2]
          if attrs.id is undefined
            attrs.id = -> attrs._id = uniqueId()
          events.push (data) ->
            if path = data[name].model
              params = [attrs._id || attrs.id, 'html', +escaped]
              params[3] = partial  if partial
              model.__events.bind path, params
      stack.push ['chars', text]  if text
      stack.push ['end', 'span']  if wrap
      chars post  if post

    end: (tag) ->
      stack.push ['end', tag]

  for item in stack
    pushValue = (value, quote) ->
      if value && value.call
        htmlIndex = html.push(value, '') - 1
      else
        html[htmlIndex] += if quote then quoteAttr value else value

    switch item[0]
      when 'start'
        html[htmlIndex] += '<' + item[1]
        for key, value of item[2]
          html[htmlIndex] += ' ' + key + '='
          pushValue value, true
        html[htmlIndex] += '>'
      when 'chars'
        pushValue item[1]
      when 'end'
        html[htmlIndex] += '</' + item[1] + '>'

  (data, obj) ->
    rendered = ((if item && item.call then item data else item) for item in html).join ''
    event data for event in events
    return rendered

simpleView = (name, view) ->
  (datum) ->
    path = datum.model
    model = view.model
    text = if path then model.get path else datum
    model.__events.bind path, ['$doc', 'prop', 'title']  if path and name is 'Title'
    # Remove leading whitespace and newlines
    return text && text.replace /^[\w]*([^\n]*)/g, '$1'

