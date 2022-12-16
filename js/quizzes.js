"use strict";

function draw_svg_line(svg, x1, y1, x2, y2, w, data, onclick) {
    const path_line = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    var s_line = `M ${x1} ${y1} L ${x2} ${y2} `;
    path_line.setAttribute('d', s_line);
    path_line.setAttribute('stroke-linecap', 'round');
    path_line.setAttribute('stroke-linejoin', 'round');
    path_line.setAttribute('stroke-width', w);
    svg.appendChild(path_line);
    if (data)
      path_line.setAttribute('data-match', data);
    if (onclick)
      path_line.addEventListener('click', onclick);
}

function matching_line_click() {
  var root_div = $(this).parents('div.match_root');
  $(this).remove();
  root_div.trigger('change');
}

function make_match(root_div, left, right) {
  var svg = root_div.find('svg');
  var pair = left.data('quiz-num') + ',' + right.data('quiz-num');
  draw_svg_line(svg[0],
    0, (left[0].offsetTop + left[0].offsetHeight / 2) / root_div[0].offsetHeight * 1000,
    1000, (right[0].offsetTop + right[0].offsetHeight / 2) / root_div[0].offsetHeight * 1000,
    '15', pair, matching_line_click);
}

function matching_click() {
  var d = $(this);
  var root_div = d.parent().parent();
  var selected = root_div.find('div.match_side.match_selected');
  if (selected.length == 0) {
    d.addClass('match_selected');
  }
  else if (selected.length == 1 && selected[0] == d[0]) {
    selected.removeClass('match_selected');
  }
  else if (selected.length == 1 && selected.data('match-side') == d.data('match-side')) {
    selected.removeClass('match_selected');
    d.addClass('match_selected');
  }
  else if (selected.length == 1 && selected.data('match-side') != d.data('match-side')) {
    selected.removeClass('match_selected');
    var left = selected.data('match-side') == 'left' ? selected : d;
    var right = selected.data('match-side') == 'right' ? selected : d;
    make_match(root_div, left, right);
    root_div.trigger('change');
  }
}

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

      if (question.type === 'radiogroup' || question.type === 'checkbox' || question.type === 'matching') {
        question.choices = $.map(quiz.children('Choice').remove(), function(choice, i) {
          return { value: i + 1, text: choice.innerHTML, side: choice.getAttribute('side') };
        });
      }
      var qid = 'p' + cpid + '_q' + quiz_count;
      var make_choices = function (type) {
        var choices_div = $('<div>').appendTo(quiz);
        for (var i = 0; i < question.choices.length; ++i) {
          var para = $('<p>').appendTo(choices_div);
          var label = $('<label>').html(question.choices[i].text).appendTo(para);
          var inp = $('<input type="' + type + '" name="' + qid +
            '" value="' + question.choices[i].value + '"/>').
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
        var inp = $('<input type="text" name="' + qid + '" class="bordered"/>').
          attr('pattern', '\\S+').
          appendTo(quiz).change(changed_callback);
      }
      else if (question.type === 'matching') {
        var choices_div = $('<div class="match_root" id="' + qid + '">').appendTo(quiz).change(changed_callback);
        var choices_div_left = $('<div>').appendTo(choices_div);
        var drawing_space = $(
          '<svg version="1.1" viewBox="0 0 1000 1000" preserveAspectRatio="none" class="match_drawing_space"></svg>').
          appendTo(choices_div);
        var choices_div_right = $('<div>').appendTo(choices_div);
        var left_count = 0, right_count = 0;
        for (var i = 0; i < question.choices.length; ++i) {
          var cnt = question.choices[i].side === 'left' ? ++left_count : ++right_count;
          var ch_div = $('<div class="match_side bordered">').html(question.choices[i].text).data('quiz-num', cnt).
            appendTo(question.choices[i].side === 'left' ? choices_div_left : choices_div_right).
            data('match-side', question.choices[i].side).
            click(matching_click);
        }
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
    else if (question.type === 'matching') {
      var root_div = $('div#p' + cpid + '_q' + (i + 1));
      root_div.find('svg path').remove();
      if (answers[i])
        answers[i].split(' ').forEach(function (a) {
          var lr = a.split(',');
          var left = root_div.find('div.match_side').filter(
            function (_, e) { return $(e).data('match-side') == 'left' && $(e).data('quiz-num') == lr[0]; });
          var right = root_div.find('div.match_side').filter(
            function (_, e) { return $(e).data('match-side') == 'right' && $(e).data('quiz-num') == lr[1]; })
          if (left.length && right.length)
            make_match(root_div, left, right);
        });
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
  else if (q_elem.attr('type') === "text") {
    value = q_elem.val()
  }
  else if (q_elem.hasClass('match_root')) {
    value = q_elem.find('svg path').
      map(function (_, el) { return el.getAttribute('data-match'); }).toArray().join(' ');
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
