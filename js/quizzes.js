"use strict";

function init_quizzes() {
  $('.problem_text').each(function() {
    var cpid = this.id.substr(1);
    var problem_text = $(this);
    var questions = problem_text.data('quiz');
    if (!questions) {
      questions = [];
      problem_text.data('quiz', questions)
    }
    var editor = Editor.get_editor(problem_text);
    var quiz_count = 0;
    var editor_changed_callback = fill_quiz_forms.bind(null, editor, problem_text);
    problem_text.find('Quiz').each(function() {
      var quiz = $(this);
      if (quiz.hasClass('active')) return;
      quiz.addClass('active');
      quiz.find('Text').each(function() {
        $(this).replaceWith($('<p></p>', { html: $(this).html() }));
      });
      quiz_count++;
      var question = { 
        type: quiz.attr('type'), 
        name: 'Quiz' + quiz_count,
      };
      var changed_callback = function() {
        var quiz_number = quiz_count;
        return function () { quiz_value_changed(editor, this, quiz_number, editor_changed_callback); };
      }();

      if (question.type === 'radiogroup' || question.type === 'checkbox') {
        question.choices = $.map(quiz.children('Choice').remove(), function(choice, i) {
          return { value: i + 1, text: choice.innerHTML };
        });
      }
      var make_choices = function (type) {
        var choices_div = $('<div>').appendTo(quiz);
        for (var i = 0; i < question.choices.length; ++i) {
          var para = $('<p>').appendTo(choices_div);
          var label = $('<label>').html(question.choices[i].text).appendTo(para);
          var inp = $('<input type="' + type + '" name="p' + cpid + '_q' + quiz_count + '" value="' + question.choices[i].value + '"/>').
            prependTo(label).change(changed_callback);
        }
      };
      if (question.type === 'radiogroup') {
        make_choices('radio');
      }
      else if (question.type === 'checkbox') {
        make_choices('checkbox');
      }
      else if (question.type === 'text') {
        var inp = $('<input type="text" name="p' + cpid + '_q' + quiz_count + '" class="bordered"/>').attr('pattern', '\\S+').
          appendTo(quiz).change(changed_callback);
      }
      questions.push(question);
    });
    if (quiz_count) {
      problem_text.find('.show_editor').click(); // Toggle editor to hidden.
      problem_text.find('.editor_only').hide();
      editor.getSession().addEventListener('change', editor_changed_callback);
      fill_quiz_forms(editor, problem_text);
      setTimeout(function() {
        $('.problem_text Quiz').each(function(_, quiz) { is_quiz_input_valid($(quiz)); } );
      }, 0);
    }
  });
}

function fill_quiz_forms(editor, problem_text) {
  var questions = problem_text.data('quiz');
  var cpid = problem_text[0].id.substr(1);
  var answers = editor.getValue().split(/\r?\n/);
  for (var i = 0; i < questions.length; ++i) {
    var question = questions[i];
    var inp = problem_text.find('input[name=p' + cpid + '_q' + (i + 1) + ']');
    if (question.type === 'radiogroup') {
      inp.each(function () {
        this.checked = this.value === answers[i];
      });
    }
    else if (question.type === 'checkbox') {
      var answer_items = {};
      if (answers[i])
        answers[i].split(' ').forEach(function (a) { answer_items[a] = 1; });
      inp.each(function () {
        this.checked = answer_items[this.value];
      });
    }
    else if (question.type === 'text') {
      inp.val(answers[i]);
    }
  }
}

function quiz_value_changed(editor, question, question_number, editor_changed_callback) {
  editor.getSession().removeEventListener('change', editor_changed_callback);
  var answers = editor.getValue().split('\n');
  if (answers.length >= question_number) {
    editor.moveCursorTo(question_number - 1);
    editor.navigateLineEnd();
    editor.removeToLineStart();
  }
  else {
    editor.moveCursorTo(answers.length);
    for (var i = answers.length; i < question_number; ++i)
      editor.insert('\n');
  }

  var q_elem = $(question);
  // TODO: Add UI for unanswering question.
  var value;
  if (q_elem.attr('type') === "radio")
    value = q_elem.val()
  else if (q_elem.attr('type') === "checkbox") {
    value = q_elem.parent().parent().parent().find('input:checked').
      map(function (_, el) { return el.value; }).toArray().join(' ');
  }
  else if (q_elem.attr('type') === "checkbox") {
    value = q_elem.val()
  }
  if (value !== undefined)
    editor.insert(value);
  editor.getSession().addEventListener('change', editor_changed_callback);
}

function is_quiz_input_valid(quiz, msg) {
  var input = quiz.find('input[type="text"]')[0];
  if (!input) return true;
  input.setCustomValidity('');
  if (input.checkValidity()) return true;
  input.setCustomValidity(msg);
  quiz.find('input[type="submit"]').click();
  return false;
}

function is_all_quiz_input_valid(form, msg) {
  var is_valid = true;
  var problem_text = form.parents('.problem_text');
  problem_text.find('Quiz').each(function(_, quiz) {
    if (!is_quiz_input_valid($(quiz), msg))
      is_valid = false;
  });
  return is_valid;
}
