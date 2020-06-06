function init_quizzes() {
  Survey.StylesManager.applyTheme('default');
  $('.problem_text').each(function() {
    var survey_models = [];
    var problem_text = $(this);
    var editor = Editor.get_editor(problem_text);
    var quiz_count = 0;
    var editor_changed_callback = fill_quiz_forms.bind(null, editor, problem_text);
    problem_text.find('Quiz').each(function() {
      var quiz = $(this);
      if (quiz.find('form').length) return;
      quiz.find('Text').each(function() {
        $(this).replaceWith($('<p></p>', {html: $(this).html()}));
      });
      var form = $('<form/>');
      quiz.addClass('active').append(form);
      form.attr('onsubmit', 'return false;');
      var question = { 
        type: quiz.attr('type'), 
        name: 'Quiz' + quiz_count
      };
      if (question.type === 'radiogroup' || question.type === 'checkbox')
        question.choices = $.map(quiz.children('Choice').remove(), function(choice, i) {
          return { value: i + 1, text: choice.innerHTML };
        });
      var survey = new Survey.Model({
        questionTitleTemplate: '{no}',
        questions: [ question ],
        showNavigationButtons: false,
        showQuestionNumbers: 'off'
      });
      survey.onTextMarkdown.add(function(survey, options) {
        options.html = options.text;
      });
      var survey_changed_callback = function() {
        var quiz_number = quiz_count;
        return function (survey, options) { survey_value_changed(editor, quiz_number, survey, editor_changed_callback); };
      }();
      survey.onValueChanged.add(survey_changed_callback);
      form.Survey({ model: survey });
      form.append('<input type="submit" hidden="true">');
      if (question.type === 'text')
        quiz.find('input').attr('pattern', '\\S+');
      survey.changed_callback = survey_changed_callback;
      survey_models.push(survey);
      quiz_count++;
    });
    if (quiz_count) {
      var check_box = problem_text.find('.show_editor');
      check_box[0].checked = false;
      check_box.click();
      problem_text.find('.editor_only').hide();
      problem_text.data('survey_models', survey_models);
      editor.getSession().addEventListener('change', editor_changed_callback);
      fill_quiz_forms(editor, problem_text);
      setTimeout(function() {
        $('.problem_text Quiz').each(function(_, quiz) { is_quiz_input_valid($(quiz)); } );
      }, 0);
    }
  });
}

function fill_quiz_forms(editor, problem_text) {
  var survey_models = problem_text.data('survey_models');
  var answers = editor.getValue().split(/\r?\n/);
  for (var i = 0; i < survey_models.length; ++i) {
    var sm = survey_models[i];
    sm.onValueChanged.remove(sm.changed_callback);
    var question = sm.getQuestionByName('Quiz' + i);
    if (question.getType() === 'checkbox' && answers[i] !== undefined)
      question.value = (answers[i] === '') ? [] : answers[i].split(' ');
    else
      question.value = answers[i];
    sm.onValueChanged.add(sm.changed_callback);
  }
}
  
function survey_value_changed(editor, question_number, survey, editor_changed_callback) {
  var question = survey.getQuestionByName('Quiz' + question_number);
  editor.getSession().removeEventListener('change', editor_changed_callback);
  var answers = editor.getValue().split('\n');
  if (answers.length > question_number) {
    editor.moveCursorTo(question_number);
    editor.navigateLineEnd();
    editor.removeToLineStart();
  }
  else {
    editor.moveCursorTo(answers.length);
    for (var i = answers.length; i <= question_number; ++i)
      editor.insert('\n');
  }
  // TODO: Add UI for unanswering question.
  if (question.value === undefined) return;
  if (question.getType() === 'checkbox')
    editor.insert(question.value.join(' '));
  else
    editor.insert(question.value);
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
