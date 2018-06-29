$(document).ready(function () {
  $('textarea[data-editor]').each(function() {
   
    var textarea = $(this);
    var mode = textarea.data('editor');
    var editDiv = $('<div>', {
      position: 'relative',
      width: textarea.attr('rows') ? textarea.width() : $( window ).width(),
      height: textarea.attr('cols') ? textarea.height() : $( window ).height(),
      'class': textarea.attr('class')
    }).insertBefore(textarea);
    textarea.css('display', 'none');
    var editor = ace.edit(editDiv[0]);
    editor.renderer.setShowGutter(textarea.data('gutter'));
    editor.getSession().setValue(textarea.val());
    editor.getSession().setMode("ace/mode/" + mode);
    editor.setTheme("ace/theme/chrome");

    editor.setOptions({
        fontSize: "12pt",
    });

    textarea.closest('form').submit(function() {
      textarea.val(editor.getSession().getValue());
    })

  });

  if ($('.submit_hidden' )) {
    $('.submit_hidden' ).css('display', 'none');
    $(".submit" ).on( "click", () => { $('.submit_hidden' ).click(); });
  }

});