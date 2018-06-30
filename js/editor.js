$(document).ready(function () {
  $('textarea[data-editor]').each(function() {
   
    if (!ace) return;
    var textarea = $(this);
    var mode = textarea.data('editor');
    var editDiv = $('<div>', {
      position: 'relative',
      width: textarea.width(),
      height: textarea.height(),
      'class': 'editor',
    }).insertBefore(textarea);

    textarea.css('display', 'none');
    var editor = ace.edit(editDiv[0]);
    editor.renderer.setShowGutter(textarea.data('gutter'));
    editor.getSession().setValue(textarea.val());
    editor.getSession().setMode('ace/mode/' + mode);
    editor.setTheme('ace/theme/chrome');

    editor.setOptions({
        fontSize: '14px',
    });

  });
});
