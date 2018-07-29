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
    }).css({ position: 'relative' }).insertBefore(textarea);

    editorContainer.wrap("<div class='resizable'></div>");
    var resizable =  $('.resizable');
    resizable.wrap("<div class='container'></div>");
    resizable.append("<div class='resizable-line resizable-right-line'></div>");
    resizable.append("<div class='resizable-line resizable-bottom-line'></div>");

    var heightResize = ('.resizable-bottom-line');
    var widthResize = ('.resizable-right-line');

    textarea.hide();
    var editor = ace.edit(editorContainer[0]);
    editor.renderer.setShowGutter(textarea.data('gutter'));
    editor.getSession().setValue(textarea.val());
    editor.getSession().setMode('ace/mode/' + mode);
    editor.setTheme('ace/theme/chrome');
    
    editor.setOptions({
      fontSize: '14px',
    });

    var canResize = false;
    var resizableContainer = $('.container');
    var top_offset = editorContainer.offset().top;

    mouseupResize = (widthOrHight, value) => {
      $(document).unbind('mousemove');
      editorContainer.css(widthOrHight, value).css('opacity', 1);
      editor.resize();
      window.dragging = false;
    }

    mousedownResize = widthOrHight => {
      window.dragging = true;
      editorContainer.css( 'opacity', 0 );
      $(document).mousemove(e => {
        canResize = true;
        var value = widthOrHight == 'width' ? e.pageX : e.pageY - top_offset;
        editorContainer.css(widthOrHight, value );
        resizableContainer.css(widthOrHight, value);
        editor.resize();
      });
    }

    $(heightResize).mouseup(e => {
      if (window.dragging && canResize) {
        var currentHight = e.pageY - top_offset;
        mouseupResize('height', currentHight);
        canResize = false;
      }
    });

    $(widthResize).mouseup(e => {
      if (window.dragging && canResize) {
        mouseupResize('width', e.pageX);
        canResize = false;
      }
    });

    $(heightResize).mousedown(e => {
      e.preventDefault();
      mousedownResize('height');
    });

    $(widthResize).mousedown(e => {
      e.preventDefault();
      mousedownResize('width');
    });

  });
});
