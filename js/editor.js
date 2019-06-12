$(document).ready(init_editors);

function get_editor(context) { return context.find('textarea[data-id]'); }

// Container is inserted before the original textarea. See init_editors().
function get_editor_container(context) { return get_editor(context).prev(); }

function init_editors() {
  if (!ace) return;
  // Ace is broken on mobile browsers.
  if (/Mobi|Android/i.test(navigator.userAgent)) return;

  var storage;
  try {
    var uid = new Date;
    (storage = window.localStorage).setItem(uid, uid);
    var fail = storage.getItem(uid) != uid;
    storage.removeItem(uid);
    fail && (storage = false);
  } catch (exception) {}

  get_editor($('body')).each(function() {
    var textarea = $(this);
    var mode = textarea.data('editor');
    textarea.width(Math.min(textarea.width(), document.body.clientWidth - 8));
    var editorContainer = $('<div>', {
      id: textarea.data('id'),
      width: textarea.width(),
      height: textarea.height(),
      'class': 'bordered',
    }).insertBefore(textarea);

    editorContainer.wrap('<div class="resizable"></div>');
    var resizable = $(editorContainer.parent());

    resizable.css({ width: textarea.width(), height: textarea.height() });

    var widthResize = $('<div class="resizable_line resizable_right_line"></div>');
    var heightResize = $('<div class="resizable_line resizable_bottom_line"></div>');
    resizable.append(heightResize).append(widthResize);

    textarea.hide();
    var editor = ace.edit(editorContainer[0]);
    editor.renderer.setShowGutter(textarea.data('gutter'));
    var sess = editor.getSession();
    sess.setValue(textarea.val());
    sess.setMode('ace/mode/' + mode);
    sess.setOption('useWorker', false);
    editor.commands.addCommand({
      name: 'toggleWrapMode',
      bindKey: { win: 'Ctrl-Alt-w', mac: 'Command-Alt-w' },
      exec: function(ed) { ed.getSession().setUseWrapMode(!ed.getSession().getUseWrapMode()); }
    });

    editor.commands.addCommand({
      name: 'removeline',
      bindKey: { win: 'Ctrl-Y', mac: 'Command-Y' },
      exec: function(ed) { ed.removeLines(); },
      scrollIntoView: 'cursor',
      multiSelectAction: 'forEachLine'
    })

    editor.setTheme('ace/theme/chrome');

    editor.setOptions({
      enableBasicAutocompletion: true,
      fontSize: '14px',
    });

    if (storage) {
      get_editor_session(editor);
      var save_editor_session = function() {
        localStorage.setItem(editor.container.id, JSON.stringify(session_to_json(editor)));
      }
      sess.on('change', save_editor_session);
      sess.selection.on('changeSelection', save_editor_session);
      sess.selection.on('changeCursor', save_editor_session);
      sess.on('changeFold', save_editor_session);
      sess.on('changeScrollLeft', save_editor_session);
      sess.on('changeScrollTop', save_editor_session);
    }

    textarea.closest('form').on('submit', function() {
      textarea.val(editor.getSession().getValue());
      if (this.np)
        this.np.value = navigator.plugins.length;
    });

    var doc = $(document);

    var mouseHandler = function(e, widthOrHeight) {
        var value = widthOrHeight == 'width' ?
          e.pageX : e.pageY - editorContainer.offset().top;
        editorContainer.css(widthOrHeight, value);
        resizable.css(widthOrHeight, value);
    };

    var mousedownResize = function(widthOrHeight) {
      $('body').css({ cursor: widthOrHeight == 'width' ? 'col-resize' : 'row-resize' });
      doc.mousemove(function(e) {
        mouseHandler(e, widthOrHeight);
        if (e.pageY + 40 > doc.height())
          doc.scrollTop(doc.scrollTop() + 10);
      });
      doc.mouseup(function(e) {
        doc.unbind('mousemove');
        doc.unbind('mouseup');
        $('body').css({ cursor: '' });
        mouseHandler(e, widthOrHeight);
        editor.resize();
      });
    };

    heightResize.mousedown(function(e) {
      e.preventDefault();
      mousedownResize('height');
    });

    widthResize.mousedown(function(e) {
      e.preventDefault();
      mousedownResize('width');
    });

  });

  function get_editor_session(editor) {
    var state = JSON.parse(localStorage.getItem(editor.container.id));
    if (!state) return;
    json_to_session(editor, state);
  }

  function json_to_session(editor, state) {
    var sess = editor.getSession();
    sess.setValue(state.content);
    editor.selection.fromJSON(state.selection);
    sess.setOptions(state.options);
    sess.setMode(state.mode);
    sess.setScrollTop(state.scrollTop);
    sess.setScrollLeft(state.scrollLeft);
    sess.$undoManager.$undoStack = state.history.undo;
    sess.$undoManager.$redoStack = state.history.redo;
  }

  function session_to_json(editor) {
    return {
      content: editor.getSession().getValue(),
      selection: editor.getSelection().toJSON(),
      options: editor.getSession().getOptions(),
      mode: editor.session.getMode().$id,
      scrollTop: editor.session.getScrollTop(),
      scrollLeft: editor.session.getScrollLeft(),
      history: {
        undo: editor.session.getUndoManager().$undoStack,
        redo: editor.session.getUndoManager().$redoStack
      },
    }
  }
}

function add_error(errors, line, error_regexp) {
  var m = line.match(error_regexp);
  if (!m) return;
  if (errors[m[1]])
    errors[m[1]] += "\n" + line;
  else
    errors[m[1]] = line;
}

function highlight_errors(error_list_id, error_list_regexp, editor_id) {
  var co = document.getElementById(error_list_id);
  if (!co) return;
  var co_text = co.textContent;
  if (!co_text) return;
  var editor = ace.edit(document.getElementById(editor_id));
  if (!editor) return;
  var Range = ace.require('ace/range').Range;
  var co_lines = co_text.split('\n');
  var errors = {};
  for (var i = 0; co_lines.length > i; ++i) {
    for (var j = 0; error_list_regexp.length > j; ++j) {
      add_error(errors, co_lines[i], error_list_regexp[j]);
    }
  }
  var session = editor.getSession();
  var annotations = [];
  for (var e in errors) {
    session.addMarker(new Range(e - 1, 0, e - 1, 1), 'ace_highlight_errors', 'fullLine');
    annotations.push({ row: e - 1, column: 0, text: errors[e], type: 'error' });
  }
  session.setAnnotations(annotations);
}

function set_syntax(editor_id, select_id) {
  $('#' + select_id).on('change', function(e) {
    var editor = ace.edit(editor_id);
    if (!editor) return;
    var mode = $('option:selected', this).attr('editor-syntax');
    editor.getSession().setMode({
      path: mode ? 'ace/mode/' + mode : 'ace/mode/plain_text',
    });
  });
}
