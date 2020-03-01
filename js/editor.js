$(document).ready(init_editors);

var editor_theme = 'chrome';

function get_editor(context) { return context.find('textarea[data-id]'); }

// Container is inserted before the original textarea. See init_editors().
function get_editor_container(context) { return get_editor(context).prev(); }

function init_editors(callback) {
  if (!ace) return;
  // Ace is broken on mobile browsers.
  if (/Mobi|Android/i.test(navigator.userAgent)) return;

  var storage;
  var hash_key;
  var MD5 = function(d){result = M(V(Y(X(d),8*d.length)));return result.toLowerCase()};function M(d){for(var _,m="0123456789ABCDEF",f="",r=0;r<d.length;r++)_=d.charCodeAt(r),f+=m.charAt(_>>>4&15)+m.charAt(15&_);return f}function X(d){for(var _=Array(d.length>>2),m=0;m<_.length;m++)_[m]=0;for(m=0;m<8*d.length;m+=8)_[m>>5]|=(255&d.charCodeAt(m/8))<<m%32;return _}function V(d){for(var _="",m=0;m<32*d.length;m+=8)_+=String.fromCharCode(d[m>>5]>>>m%32&255);return _}function Y(d,_){d[_>>5]|=128<<_%32,d[14+(_+64>>>9<<4)]=_;for(var m=1732584193,f=-271733879,r=-1732584194,i=271733878,n=0;n<d.length;n+=16){var h=m,t=f,g=r,e=i;f=md5_ii(f=md5_ii(f=md5_ii(f=md5_ii(f=md5_hh(f=md5_hh(f=md5_hh(f=md5_hh(f=md5_gg(f=md5_gg(f=md5_gg(f=md5_gg(f=md5_ff(f=md5_ff(f=md5_ff(f=md5_ff(f,r=md5_ff(r,i=md5_ff(i,m=md5_ff(m,f,r,i,d[n+0],7,-680876936),f,r,d[n+1],12,-389564586),m,f,d[n+2],17,606105819),i,m,d[n+3],22,-1044525330),r=md5_ff(r,i=md5_ff(i,m=md5_ff(m,f,r,i,d[n+4],7,-176418897),f,r,d[n+5],12,1200080426),m,f,d[n+6],17,-1473231341),i,m,d[n+7],22,-45705983),r=md5_ff(r,i=md5_ff(i,m=md5_ff(m,f,r,i,d[n+8],7,1770035416),f,r,d[n+9],12,-1958414417),m,f,d[n+10],17,-42063),i,m,d[n+11],22,-1990404162),r=md5_ff(r,i=md5_ff(i,m=md5_ff(m,f,r,i,d[n+12],7,1804603682),f,r,d[n+13],12,-40341101),m,f,d[n+14],17,-1502002290),i,m,d[n+15],22,1236535329),r=md5_gg(r,i=md5_gg(i,m=md5_gg(m,f,r,i,d[n+1],5,-165796510),f,r,d[n+6],9,-1069501632),m,f,d[n+11],14,643717713),i,m,d[n+0],20,-373897302),r=md5_gg(r,i=md5_gg(i,m=md5_gg(m,f,r,i,d[n+5],5,-701558691),f,r,d[n+10],9,38016083),m,f,d[n+15],14,-660478335),i,m,d[n+4],20,-405537848),r=md5_gg(r,i=md5_gg(i,m=md5_gg(m,f,r,i,d[n+9],5,568446438),f,r,d[n+14],9,-1019803690),m,f,d[n+3],14,-187363961),i,m,d[n+8],20,1163531501),r=md5_gg(r,i=md5_gg(i,m=md5_gg(m,f,r,i,d[n+13],5,-1444681467),f,r,d[n+2],9,-51403784),m,f,d[n+7],14,1735328473),i,m,d[n+12],20,-1926607734),r=md5_hh(r,i=md5_hh(i,m=md5_hh(m,f,r,i,d[n+5],4,-378558),f,r,d[n+8],11,-2022574463),m,f,d[n+11],16,1839030562),i,m,d[n+14],23,-35309556),r=md5_hh(r,i=md5_hh(i,m=md5_hh(m,f,r,i,d[n+1],4,-1530992060),f,r,d[n+4],11,1272893353),m,f,d[n+7],16,-155497632),i,m,d[n+10],23,-1094730640),r=md5_hh(r,i=md5_hh(i,m=md5_hh(m,f,r,i,d[n+13],4,681279174),f,r,d[n+0],11,-358537222),m,f,d[n+3],16,-722521979),i,m,d[n+6],23,76029189),r=md5_hh(r,i=md5_hh(i,m=md5_hh(m,f,r,i,d[n+9],4,-640364487),f,r,d[n+12],11,-421815835),m,f,d[n+15],16,530742520),i,m,d[n+2],23,-995338651),r=md5_ii(r,i=md5_ii(i,m=md5_ii(m,f,r,i,d[n+0],6,-198630844),f,r,d[n+7],10,1126891415),m,f,d[n+14],15,-1416354905),i,m,d[n+5],21,-57434055),r=md5_ii(r,i=md5_ii(i,m=md5_ii(m,f,r,i,d[n+12],6,1700485571),f,r,d[n+3],10,-1894986606),m,f,d[n+10],15,-1051523),i,m,d[n+1],21,-2054922799),r=md5_ii(r,i=md5_ii(i,m=md5_ii(m,f,r,i,d[n+8],6,1873313359),f,r,d[n+15],10,-30611744),m,f,d[n+6],15,-1560198380),i,m,d[n+13],21,1309151649),r=md5_ii(r,i=md5_ii(i,m=md5_ii(m,f,r,i,d[n+4],6,-145523070),f,r,d[n+11],10,-1120210379),m,f,d[n+2],15,718787259),i,m,d[n+9],21,-343485551),m=safe_add(m,h),f=safe_add(f,t),r=safe_add(r,g),i=safe_add(i,e)}return Array(m,f,r,i)}function md5_cmn(d,_,m,f,r,i){return safe_add(bit_rol(safe_add(safe_add(_,d),safe_add(f,i)),r),m)}function md5_ff(d,_,m,f,r,i,n){return md5_cmn(_&m|~_&f,d,_,r,i,n)}function md5_gg(d,_,m,f,r,i,n){return md5_cmn(_&f|m&~f,d,_,r,i,n)}function md5_hh(d,_,m,f,r,i,n){return md5_cmn(_^m^f,d,_,r,i,n)}function md5_ii(d,_,m,f,r,i,n){return md5_cmn(m^(_|~f),d,_,r,i,n)}function safe_add(d,_){var m=(65535&d)+(65535&_);return(d>>16)+(_>>16)+(m>>16)<<16|65535&m}function bit_rol(d,_){return d<<_|d>>>32-_};
  var save_editor_session = function(editor) {
    localStorage.setItem(editor.container.id, JSON.stringify(session_to_json(editor)));
  }
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
    editor.commands.addCommands([
    {
      name: 'toggleWrapMode',
      bindKey: { win: 'Ctrl-Alt-w', mac: 'Command-Alt-w' },
      exec: function(ed) { ed.getSession().setUseWrapMode(!ed.getSession().getUseWrapMode()); }},
    {
      name: 'toggleInvisibleChars',
      bindKey: { win: 'Ctrl-Alt-v', mac: 'Command-Alt-v' },
      exec: function(ed) { ed.setShowInvisibles(!ed.getShowInvisibles()); }
    }]);

    editor.commands.addCommand({
      name: 'removeline',
      bindKey: { win: 'Ctrl-Y', mac: 'Command-Y' },
      exec: function(ed) { ed.removeLines(); },
      scrollIntoView: 'cursor',
      multiSelectAction: 'forEachLine'
    })

    editor.setTheme('ace/theme/' + editor_theme);

    editor.setOptions({
      enableBasicAutocompletion: true,
      fontSize: '14px',
    });

    hash_key = editor.container.id + '_hash';
    if (storage) {
      var new_hash = MD5(unescape(encodeURIComponent(editor.getSession().getValue())));
      var old_hash = localStorage.getItem(hash_key);
      if (!old_hash) localStorage.setItem(hash_key, new_hash);
      get_editor_session(editor, new_hash, old_hash);
      var save_session = save_editor_session.bind(null, editor);
      sess.on('change', save_session);
      sess.selection.on('changeSelection', save_session);
      sess.selection.on('changeCursor', save_session);
      sess.on('changeFold', save_session);
      sess.on('changeScrollLeft', save_session);
      sess.on('changeScrollTop', save_session);
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

  function get_editor_session(editor, new_hash, old_hash) {
    var state = JSON.parse(localStorage.getItem(editor.container.id));
    if (!state) return;
    if (new_hash != old_hash) {
      var msg = $('#different_versions_msg').text();
      if (msg)
        $('.messages').text(msg);
      localStorage.setItem(hash_key, new_hash);
      json_to_session(editor, state, editor.getSession().getValue());
    } else
      json_to_session(editor, state);
  }

  function json_to_session(editor, state, value) {
    var sess = editor.getSession();
    sess.setValue(state.content);
    editor.selection.fromJSON(state.selection);
    sess.setOptions(state.options);
    sess.setMode(state.mode);
    sess.setScrollTop(state.scrollTop);
    sess.setScrollLeft(state.scrollLeft);
    sess.$undoManager.$undoStack = state.history.undo;
    sess.$undoManager.$redoStack = state.history.redo;
    if (value) {
      sess.doc.setValue(value);
      sess.selection.moveTo(0, 0);
    }
    // Wait until ace-mode is loaded
    setTimeout(save_editor_session.bind(null, editor), 500);
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
  if (callback !== 'undefined') callback();
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

function reset_localstorage(editor_id) {
  try {
    localStorage.removeItem(editor_id);
    document.location.reload();
  } catch(exception) {}
}
