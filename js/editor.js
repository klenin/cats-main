$(document).ready(function () {
  $('textarea[data-editor]').each(function() {
    if (!ace) return;

    var textarea = $(this);
    var mode = textarea.data('editor');
    var editorContainer = $('<div>', {
      id: textarea.data('id'),
      width: textarea.width(),
      height: textarea.height(),
      'class': 'bordered',
    }).css({position: 'relative'}).insertBefore(textarea);

    editorContainer.wrap('<div class="resizable"></div>');
    var resizable = $(editorContainer.parent());
    resizable.wrap('<div class="container"></div>');

    resizable.css('width', textarea.width());
    resizable.css('height', textarea.height());

    var widthResize = $('<div class="resizable-line resizable-right-line"></div>');
    var heightResize = $('<div class="resizable-line resizable-bottom-line"></div>');
    resizable.append(heightResize).append(widthResize);

    textarea.hide();
    var editor = ace.edit(editorContainer[0]);
    editor.renderer.setShowGutter(textarea.data('gutter'));
    editor.getSession().setValue(textarea.val());
    editor.getSession().setMode('ace/mode/' + mode);
    editor.setTheme('ace/theme/chrome');

    editor.setOptions({
      fontSize: '14px',
    });

    textarea.closest('form').submit(function() {
      textarea.val(editor.getSession().getValue());
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
});
