var Editor;

$(document).ready(function() {
  Editor = new Editor();
  Editor.init_editors();
});

function Editor() {
  try {
    var uid = new Date();
    (this.storage = window.localStorage).setItem(uid, uid);
    var fail = this.storage.getItem(uid) != uid;
    this.storage.removeItem(uid);
    fail && (this.storage = false);
  } catch (exception) {}

  this._editors = {};
  this.theme = 'chrome';

  this.get_editor = function(context) {
    var textarea = context.find('textarea[data-id]');
    var editor_id = textarea.attr('data-id');
    if (!this._has_editor(editor_id)) return null;
    return this._editors[editor_id];
  }

  this.init_editors = function() {
    var self = this;
    $('body').find('textarea[data-id]').each(function() {
      if ($(this).data('init-defer')) return;
      self.init_editor($(this).data('id'));
    });
  };

  this.init_editor = function(editor_id) {
    if (
      !ace ||
      // Ace is broken on mobile browsers.
      /Mobi|Android/i.test(navigator.userAgent) ||
      this._has_editor(editor_id)
    ) return null;

    var textarea = $("textarea[data-id='" + editor_id +"']");
    if (textarea === undefined) return;
    textarea.width(Math.min(textarea.width(), document.body.clientWidth - 8));

    var ace_editor = ace.edit(this._init_dom_elements(textarea));
    this._editors[editor_id] = ace_editor;

    this._configurate_editor(ace_editor, textarea);
    this._linkify(ace_editor);

    textarea.closest('form').on('submit', function() {
      textarea.val(ace_editor.getSession().getValue());
    });

    if (this.storage) this._setup_localstorage(editor_id);

    textarea.hide();
  };

  this.highlight_errors = function(error_list_id, error_list_regexp, editor_id) {
    if (!this._has_editor(editor_id)) return null;
    var co = document.getElementById(error_list_id);
    if (!co) return;
    var co_text = co.textContent;
    if (!co_text) return;

    var add_error = function(errors, line, error_regexp) {
      var m = line.match(error_regexp);
      if (!m) return;
      if (errors[m[1]])
        errors[m[1]] += '\n' + line;
      else
        errors[m[1]] = line;
    }

    var ace_editor = this._editors[editor_id];
    var Range = ace.require('ace/range').Range;
    var co_lines = co_text.split('\n');
    var errors = {};
    for (var i = 0; co_lines.length > i; ++i) {
      for (var j = 0; error_list_regexp.length > j; ++j) {
        add_error(errors, co_lines[i], error_list_regexp[j]);
      }
    }

    var sess = ace_editor.getSession();
    var annotations = [];
    for (var e in errors) {
      sess.addMarker(new Range(e - 1, 0, e - 1, 1), 'ace_highlight_errors', 'fullLine');
      annotations.push({ row: e - 1, column: 0, text: errors[e], type: 'error' });
    }
    sess.setAnnotations(annotations);
  };

  this.set_syntax = function(editor_id, select_id) {
    if (!this._has_editor(editor_id)) return null;
    var ace_editor = this._editors[editor_id];
    $('#' + select_id).on('change', function() {
      var mode = $('option:selected', this).attr('editor-syntax');
      ace_editor.getSession().setMode({
        path: mode ? 'ace/mode/' + mode : 'ace/mode/plain_text',
      });
    });
  };

  this.reset_localstorage = function(editor_id) {
    if (!this.storage || !this._has_editor(editor_id)) return null;
    localStorage.removeItem(editor_id);
    document.location.reload();
  };

  this.toggle_editor_visibility = function(context) {
    var ace_editor = this.get_editor(context);
    if (!ace_editor) return null;
    var textarea = context.find('textarea[data-id]');
    // Container is inserted before the original textarea. See _init_dom_elements().
    var editor_container = textarea.prev();
    if (editor_container.is(':hidden')) {
      editor_container.show();
      this._editors[editor_id].resize();
    } else
      editor_container.hide();
  };

  this._MD5 = function(d){result = M(V(Y(X(d),8*d.length)));return result.toLowerCase()};function M(d){for(var _,m="0123456789ABCDEF",f="",r=0;r<d.length;r++)_=d.charCodeAt(r),f+=m.charAt(_>>>4&15)+m.charAt(15&_);return f}function X(d){for(var _=Array(d.length>>2),m=0;m<_.length;m++)_[m]=0;for(m=0;m<8*d.length;m+=8)_[m>>5]|=(255&d.charCodeAt(m/8))<<m%32;return _}function V(d){for(var _="",m=0;m<32*d.length;m+=8)_+=String.fromCharCode(d[m>>5]>>>m%32&255);return _}function Y(d,_){d[_>>5]|=128<<_%32,d[14+(_+64>>>9<<4)]=_;for(var m=1732584193,f=-271733879,r=-1732584194,i=271733878,n=0;n<d.length;n+=16){var h=m,t=f,g=r,e=i;f=md5_ii(f=md5_ii(f=md5_ii(f=md5_ii(f=md5_hh(f=md5_hh(f=md5_hh(f=md5_hh(f=md5_gg(f=md5_gg(f=md5_gg(f=md5_gg(f=md5_ff(f=md5_ff(f=md5_ff(f=md5_ff(f,r=md5_ff(r,i=md5_ff(i,m=md5_ff(m,f,r,i,d[n+0],7,-680876936),f,r,d[n+1],12,-389564586),m,f,d[n+2],17,606105819),i,m,d[n+3],22,-1044525330),r=md5_ff(r,i=md5_ff(i,m=md5_ff(m,f,r,i,d[n+4],7,-176418897),f,r,d[n+5],12,1200080426),m,f,d[n+6],17,-1473231341),i,m,d[n+7],22,-45705983),r=md5_ff(r,i=md5_ff(i,m=md5_ff(m,f,r,i,d[n+8],7,1770035416),f,r,d[n+9],12,-1958414417),m,f,d[n+10],17,-42063),i,m,d[n+11],22,-1990404162),r=md5_ff(r,i=md5_ff(i,m=md5_ff(m,f,r,i,d[n+12],7,1804603682),f,r,d[n+13],12,-40341101),m,f,d[n+14],17,-1502002290),i,m,d[n+15],22,1236535329),r=md5_gg(r,i=md5_gg(i,m=md5_gg(m,f,r,i,d[n+1],5,-165796510),f,r,d[n+6],9,-1069501632),m,f,d[n+11],14,643717713),i,m,d[n+0],20,-373897302),r=md5_gg(r,i=md5_gg(i,m=md5_gg(m,f,r,i,d[n+5],5,-701558691),f,r,d[n+10],9,38016083),m,f,d[n+15],14,-660478335),i,m,d[n+4],20,-405537848),r=md5_gg(r,i=md5_gg(i,m=md5_gg(m,f,r,i,d[n+9],5,568446438),f,r,d[n+14],9,-1019803690),m,f,d[n+3],14,-187363961),i,m,d[n+8],20,1163531501),r=md5_gg(r,i=md5_gg(i,m=md5_gg(m,f,r,i,d[n+13],5,-1444681467),f,r,d[n+2],9,-51403784),m,f,d[n+7],14,1735328473),i,m,d[n+12],20,-1926607734),r=md5_hh(r,i=md5_hh(i,m=md5_hh(m,f,r,i,d[n+5],4,-378558),f,r,d[n+8],11,-2022574463),m,f,d[n+11],16,1839030562),i,m,d[n+14],23,-35309556),r=md5_hh(r,i=md5_hh(i,m=md5_hh(m,f,r,i,d[n+1],4,-1530992060),f,r,d[n+4],11,1272893353),m,f,d[n+7],16,-155497632),i,m,d[n+10],23,-1094730640),r=md5_hh(r,i=md5_hh(i,m=md5_hh(m,f,r,i,d[n+13],4,681279174),f,r,d[n+0],11,-358537222),m,f,d[n+3],16,-722521979),i,m,d[n+6],23,76029189),r=md5_hh(r,i=md5_hh(i,m=md5_hh(m,f,r,i,d[n+9],4,-640364487),f,r,d[n+12],11,-421815835),m,f,d[n+15],16,530742520),i,m,d[n+2],23,-995338651),r=md5_ii(r,i=md5_ii(i,m=md5_ii(m,f,r,i,d[n+0],6,-198630844),f,r,d[n+7],10,1126891415),m,f,d[n+14],15,-1416354905),i,m,d[n+5],21,-57434055),r=md5_ii(r,i=md5_ii(i,m=md5_ii(m,f,r,i,d[n+12],6,1700485571),f,r,d[n+3],10,-1894986606),m,f,d[n+10],15,-1051523),i,m,d[n+1],21,-2054922799),r=md5_ii(r,i=md5_ii(i,m=md5_ii(m,f,r,i,d[n+8],6,1873313359),f,r,d[n+15],10,-30611744),m,f,d[n+6],15,-1560198380),i,m,d[n+13],21,1309151649),r=md5_ii(r,i=md5_ii(i,m=md5_ii(m,f,r,i,d[n+4],6,-145523070),f,r,d[n+11],10,-1120210379),m,f,d[n+2],15,718787259),i,m,d[n+9],21,-343485551),m=safe_add(m,h),f=safe_add(f,t),r=safe_add(r,g),i=safe_add(i,e)}return Array(m,f,r,i)}function md5_cmn(d,_,m,f,r,i){return safe_add(bit_rol(safe_add(safe_add(_,d),safe_add(f,i)),r),m)}function md5_ff(d,_,m,f,r,i,n){return md5_cmn(_&m|~_&f,d,_,r,i,n)}function md5_gg(d,_,m,f,r,i,n){return md5_cmn(_&f|m&~f,d,_,r,i,n)}function md5_hh(d,_,m,f,r,i,n){return md5_cmn(_^m^f,d,_,r,i,n)}function md5_ii(d,_,m,f,r,i,n){return md5_cmn(m^(_|~f),d,_,r,i,n)}function safe_add(d,_){var m=(65535&d)+(65535&_);return(d>>16)+(_>>16)+(m>>16)<<16|65535&m}function bit_rol(d,_){return d<<_|d>>>32-_};

  this._has_editor = function(editor_id) {
    return this._editors.hasOwnProperty(editor_id);
  };

  this._setup_localstorage = function(editor_id) {
    var ace_editor = this._editors[editor_id];
    var sess = ace_editor.getSession();
    var save_editor_to_storage = function() {
      localStorage.setItem(editor_id, JSON.stringify({
        content: sess.getValue(),
        selection: ace_editor.getSelection().toJSON(),
        options: sess.getOptions(),
        mode: sess.getMode().$id,
        scrollTop: sess.getScrollTop(),
        scrollLeft: sess.getScrollLeft(),
        history: {
          undo: sess.getUndoManager().$undoStack,
          redo: sess.getUndoManager().$redoStack
        }
      }));
    }

    sess.on('change', save_editor_to_storage);
    sess.selection.on('changeSelection', save_editor_to_storage);
    sess.selection.on('changeCursor', save_editor_to_storage);
    sess.on('changeFold', save_editor_to_storage);
    sess.on('changeScrollLeft', save_editor_to_storage);
    sess.on('changeScrollTop', save_editor_to_storage);

    var json_to_session = function(state, textarea_value) {
      sess.setValue(state.content);
      sess.selection.fromJSON(state.selection);
      sess.setOptions(state.options);
      sess.setMode(state.mode);
      sess.setScrollTop(state.scrollTop);
      sess.setScrollLeft(state.scrollLeft);
      sess.$undoManager.$undoStack = state.history.undo;
      sess.$undoManager.$redoStack = state.history.redo;
      if (textarea_value) {
        sess.doc.setValue(textarea_value);
        sess.selection.moveTo(0, 0);
      }
      // Wait until ace-mode is loaded.
      setTimeout(save_editor_to_storage, 500);
    }

    var hash_key = editor_id + '_hash';
    var new_hash = this._MD5(unescape(encodeURIComponent(sess.getValue())));
    var old_hash = localStorage.getItem(hash_key);
    if (!old_hash) localStorage.setItem(hash_key, new_hash);
    var state = JSON.parse(localStorage.getItem(editor_id));
    if (!state) return;
    if (old_hash && (new_hash !== old_hash)) {
      var msg = $('#different_versions_msg').text();
      if (msg) $('.messages').text(msg);
      localStorage.setItem(hash_key, new_hash);
      json_to_session(state, ace_editor.getSession().getValue())
    } else
      json_to_session(state);
  };

  this._init_dom_elements = function(textarea) {
    var editor_container = $('<div>', {
      id: textarea.data('id'),
      width: textarea.width(),
      height: textarea.height(),
      'class': 'bordered',
    }).insertBefore(textarea);

    editor_container.wrap('<div class="resizable"></div>');
    var resizable = $(editor_container.parent());

    var width_resize = $('<div class="resizable_line resizable_right_line"></div>');
    var height_resize = $('<div class="resizable_line resizable_bottom_line"></div>');

    resizable.css({ width: textarea.width(), height: textarea.height() });
    resizable.append(height_resize).append(width_resize);

    var mouse_handler = function(e, width_or_height) {
      var value = width_or_height === 'width' ?
        e.pageX : e.pageY - editor_container.offset().top;
      editor_container.css(width_or_height, value);
      resizable.css(width_or_height, value);
    };
  
    var doc = $(document);
    var ace_editor = ace.edit(editor_container[0]);
    var mousedown_resize = function(width_or_height) {
      $('body').css({ cursor: width_or_height === 'width' ? 'col-resize' : 'row-resize' });
      doc.mousemove(function(e) {
        mouse_handler(e, width_or_height);
        if (e.pageY + 40 > doc.height()) doc.scrollTop(doc.scrollTop() + 10);
      });
      doc.mouseup(function(e) {
        doc.unbind('mousemove');
        doc.unbind('mouseup');
        $('body').css({ cursor: '' });
        mouse_handler(e, width_or_height);
        ace_editor.resize();
      });
    };

    height_resize.mousedown(function(e) {
      e.preventDefault();
      mousedown_resize('height');
    });

    width_resize.mousedown(function(e) {
      e.preventDefault();
      mousedown_resize('width');
    });

    return editor_container[0];
  }

  this._configurate_editor = function(ace_editor, textarea) {
    ace_editor.renderer.setShowGutter(textarea.data('gutter'));
    ace_editor.setTheme('ace/theme/' + this.theme);
    ace_editor.setOptions({
      enableBasicAutocompletion: true,
      fontSize: '14px',
    });
    var sess = ace_editor.getSession();
    sess.setValue(textarea.val());
    sess.setMode('ace/mode/' + textarea.data('editor'));
    sess.setOption('useWorker', false);
    ace_editor.commands.addCommands([
      {
        name: 'toggleWrapMode',
        bindKey: { win: 'Ctrl-Alt-w', mac: 'Command-Alt-w' },
        exec: function(ed) { ed.getSession().setUseWrapMode(!ed.getSession().getUseWrapMode()); }
      },
      {
        name: 'toggleInvisibleChars',
        bindKey: { win: 'Ctrl-Alt-v', mac: 'Command-Alt-v' },
        exec: function(ed) { ed.setShowInvisibles(!ed.getShowInvisibles()); }
      }
    ]);
    ace_editor.commands.addCommand({
      name: 'removeline',
      bindKey: { win: 'Ctrl-Y', mac: 'Command-Y' },
      exec: function(ed) { ed.removeLines(); },
      scrollIntoView: 'cursor',
      multiSelectAction: 'forEachLine'
    });
  }

  this._linkify = function(ace_editor) {
    var HoverLink = ace.require('hoverlink').HoverLink;
    ace_editor.hoverLink = new HoverLink(ace_editor);
    ace_editor.hoverLink.on('open', function(link) {
      if (link.ctrlKey)
        window.open(link.value);
      else
        document.location.href = link.value;
    })
  }
}

ace.define('hoverlink', [], function(require, exports, module) {
  'use strict';

  var oop = ace.require('ace/lib/oop');
  var event = ace.require('ace/lib/event');
  var Range = ace.require('ace/range').Range;
  var EventEmitter = ace.require('ace/lib/event_emitter').EventEmitter;

  var HoverLink = function(editor) {
    if (editor.hoverLink)
      return;
    editor.hoverLink = this;
    this.editor = editor;

    this.update = this.update.bind(this);
    this.onMouseMove = this.onMouseMove.bind(this);
    this.onMouseOut = this.onMouseOut.bind(this);
    this.onClick = this.onClick.bind(this);
    event.addListener(editor.renderer.scroller, 'mousemove', this.onMouseMove);
    event.addListener(editor.renderer.content, 'mouseout', this.onMouseOut);
    event.addListener(editor.renderer.content, 'click', this.onClick);
  };

  (function() {
    oop.implement(this, EventEmitter);

    this.token = {};
    this.range = new Range();

    this.update = function() {
      this.$timer = null;
      var editor = this.editor;
      var renderer = editor.renderer;

      var canvasPos = renderer.scroller.getBoundingClientRect();
      var offset = (this.x + renderer.scrollLeft - canvasPos.left - renderer.$padding) / renderer.characterWidth;
      var row = Math.floor((this.y + renderer.scrollTop - canvasPos.top) / renderer.lineHeight);
      var col = Math.round(offset);

      var screenPos = {row: row, column: col, side: offset - col > 0 ? 1 : -1};
      var session = editor.session;
      var docPos = session.screenToDocumentPosition(screenPos.row, screenPos.column);

      var selectionRange = editor.selection.getRange();
      if (!selectionRange.isEmpty()) {
        if (selectionRange.start.row <= row && selectionRange.end.row >= row)
          return this.clear();
      }

      var line = editor.session.getLine(docPos.row);
      if (docPos.column == line.length) {
        var clippedPos = editor.session.documentToScreenPosition(docPos.row, docPos.column);
        if (clippedPos.column != screenPos.column) {
          return this.clear();
        }
      }

      var token = this.findLink(docPos.row, docPos.column);
      this.link = token;
      if (!token) {
        return this.clear();
      }
      this.isOpen = true
      editor.renderer.setCursorStyle('pointer');

      session.removeMarker(this.marker);

      this.range =  new Range(token.row, token.start, token.row, token.start + token.value.length);
      this.marker = session.addMarker(this.range, 'ace_link_marker', 'text', true);
    };

    this.clear = function() {
      if (this.isOpen) {
        this.link = null;
        this.editor.session.removeMarker(this.marker);
        this.editor.renderer.setCursorStyle('');
        this.isOpen = false;
      }
    };

    this.getMatchAround = function(regExp, string, col) {
      var match;
      regExp.lastIndex = 0;
      string.replace(regExp, function(str) {
        var offset = arguments[arguments.length - 2];
        var length = str.length;
        if (offset <= col && offset + length >= col)
          match = { start: offset, value: str };
      });

      return match;
    };

    this.onClick = function(evt) {
      if (this.link) {
        this.link.editor = this.editor;
        this.link.ctrlKey = evt.ctrlKey;
        this._signal('open', this.link);
        this.clear()
      }
    };

    var urlRe = /\bhttps?:\/\/[\-A-Za-z0-9+&@#\/%?=~_|!:,.;]*[\-A-Za-z0-9+&@#\/%=~_|]/g;
    this.findLink = function(row, column) {
      var editor = this.editor;
      var session = editor.session;
      var line = session.getLine(row);

      var match = this.getMatchAround(urlRe, line, column);
      if (!match)
          return;

      match.row = row;
      return match;
    };

    this.onMouseMove = function(e) {
      if (this.editor.$mouseHandler.isMousePressed) {
        if (!this.editor.selection.isEmpty())
          this.clear();
        return;
      }
      this.x = e.clientX;
      this.y = e.clientY;
      this.update();
    };

    this.onMouseOut = function(e) {
      this.clear();
    };

    this.destroy = function() {
      this.onMouseOut();
      event.removeListener(this.editor.renderer.scroller, 'mousemove', this.onMouseMove);
      event.removeListener(this.editor.renderer.content, 'mouseout', this.onMouseOut);
      delete this.editor.hoverLink;
    };

  }).call(HoverLink.prototype);

  exports.HoverLink = HoverLink;

});
