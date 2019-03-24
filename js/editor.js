$(document).ready(init_editors);

function init_editors() {
  if (!ace) return;
  // Ace is broken on mobile browsers.
  if (/Mobi|Android/i.test(navigator.userAgent)) return;

  $('textarea[data-editor]').each(function() {
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

    resizable.css('width', textarea.width());
    resizable.css('height', textarea.height());

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
        exec: function(ed) {
            ed.getSession().setUseWrapMode(!ed.getSession().getUseWrapMode());
        }
    })

    editor.setTheme('ace/theme/chrome');

    editor.setOptions({
      enableBasicAutocompletion: true,
      fontSize: '14px',
    });

    textarea.closest('form').on('submit', function() {
      textarea.val(editor.getSession().getValue());
      if (this.np)
        this.np.value = navigator.plugins.length;
    });

    var top_offset = editorContainer.offset().top;
    var doc = $(document);

    var mousedownResize = function(widthOrHeight) {
      $('body').css({cursor: widthOrHeight == 'width' ? 'col-resize' : 'row-resize'});
      doc.mousemove(function(e) {
        var value = widthOrHeight == 'width' ? e.pageX : e.pageY - top_offset;
        editorContainer.css(widthOrHeight, value);
        resizable.css(widthOrHeight, value);
        if (e.pageY + 40 > doc.height()) {
            doc.scrollTop(doc.scrollTop() + 10);
        }
      });
      $(document).mouseup(function(e) {
        doc.unbind('mousemove');
        doc.unbind('mouseup');
        $('body').css({cursor: ''});
        var value = widthOrHeight == 'width' ? e.pageX : e.pageY - top_offset;
        editorContainer.css(widthOrHeight, value);
        resizable.css(widthOrHeight, value);
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
